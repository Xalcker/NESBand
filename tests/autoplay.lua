-- =============================================================================
-- autoplay.lua - Prueba automática para el modo --testrunner de Mesen 2
--
-- Recorre el juego completo como lo haría una persona:
--   título (Start) -> menú (baja a dificultad, la sube a experto, Start) ->
--   juego -> resultados
-- Durante el juego, un bot lee de la RAM cuál es la siguiente nota de cada
-- carril y presiona el botón justo en el cuadro correcto. Al final revisa:
--   - puntaje, combo y estadísticas de la pantalla de resultados
--   - sincronía: cada nota del chart debe caer en el mismo cuadro en que el
--     motor de sonido dispara una nota en el canal del jugador
--   - silenciado: si no tocas nada, el canal del jugador queda callado
-- y sale con código 0 (bien) o 1 (falla).
--
-- Variables de entorno:
--   AUTOPLAY_MODE  = perfect (default) | idle (no presiona nada: todo debe fallar)
--                    En perfect además pausa a media canción y continúa.
--   AUTOPLAY_INSTRUMENT = 0 guitarra (default), 1 teclado, 2 bajo
--   TEST_OUT       = carpeta donde dejar resultado.txt y capturas .png
--
-- Requiere que Mesen tenga habilitado "AllowIoOsAccess" (escribir archivos) y
-- que build/nesband.dbg esté junto a la ROM (para encontrar las variables).
-- =============================================================================

local mode = os.getenv("AUTOPLAY_MODE") or "perfect"
local instrument = tonumber(os.getenv("AUTOPLAY_INSTRUMENT") or "0")
local outdir = os.getenv("TEST_OUT") or "."
local mem = emu.memType.nesMemory

-- Mesen da la dirección relativa a la memoria donde vive el símbolo (RAM o
-- PRG-ROM); la convertimos a dirección de CPU para leer todo con nesMemory
local function label(name)
  local a = emu.getLabelAddress(name)
  if a == nil then error("No encontré el símbolo " .. name .. " (¿falta el .dbg?)") end
  if a.memType == emu.memType.nesPrgRom then
    return 0x8000 + a.address   -- NROM-256: la PRG-ROM completa está en $8000-$FFFF
  end
  return a.address
end

local A = {}
for _, name in ipairs({ "game_state", "song_frame", "lane_ptr_lo", "lane_ptr_hi", "score_digits",
                        "combo_digits", "chart_start", "famistudio_chn_note_counter", "notes_hit",
                        "notes_total", "max_combo", "percent", "stars", "paused" }) do
  A[name] = label(name)
end

local STATE_PLAY, STATE_RESULTS = 2, 3
local CHART_ENTRY = 5
local LANE_KEYS = { "left", "down", "right", "b", "a" }
local TIMEOUT = 7000
local PAUSE_AT, PAUSE_FRAMES = 1500, 90   -- song_frame en que se pausa, y cuánto dura

-- Registro de volumen del canal de cada instrumento, y lo que escribe apply_mute
local MUTE_REG = { [0] = 0x4000, [1] = 0x4004, [2] = 0x4008 }
local MUTE_VALUE = { [0] = 0x30, [1] = 0x30, [2] = 0x80 }

-- Botones para llegar a jugar: Start en el título; en el menú, bajar a
-- instrumento y avanzar `instrument` veces, bajar a dificultad, dos veces a
-- la derecha (de medio a experto) y Start
local MENU_SCRIPT = { [30] = "start", [50] = "down" }
for i = 1, instrument do MENU_SCRIPT[50 + i * 4] = "right" end
MENU_SCRIPT[70] = "down"
MENU_SCRIPT[74] = "right"
MENU_SCRIPT[78] = "right"
MENU_SCRIPT[90] = "start"
local SCREENSHOTS = { [25] = "captura_titulo.png", [86] = "captura_menu.png" }

local function read8(addr) return emu.read(addr, mem, false) end
local function read16(addr) return read8(addr) + read8(addr + 1) * 256 end

local function digits(addr, n)
  local v = 0
  for i = 0, n - 1 do v = v * 10 + read8(addr + i) end
  return v
end

local function write_file(name, data)
  local f = io.open(outdir .. "/" .. name, "wb")
  f:write(data)
  f:close()
end

-- Notas del chart activo: lista de {frame, mask}
local function read_chart()
  local notes = {}
  local p = read16(A.chart_start)
  while read16(p) ~= 0xFFFF do
    notes[#notes + 1] = { frame = read16(p + 2), mask = read8(p + 4) & 0x1F }
    p = p + CHART_ENTRY
  end
  return notes
end

-- Puntaje esperado si se aciertan todas (mismas reglas que gameplay.s)
local function expected(chart)
  local hits, score, combo = 0, 0, 0
  for _, n in ipairs(chart) do
    for lane = 0, 4 do
      if (n.mask >> lane) & 1 == 1 then
        hits = hits + 1
        combo = math.min(combo + 1, 999)
        score = score + 50 * math.min(combo // 10 + 1, 4)
      end
    end
  end
  return hits, score
end

local frame = 0
local pause_frame, resume_frame = nil, nil

-- Mesen pide el estado del control justo cuando el juego lo lee: ahí lo
-- reemplazamos por el guion del menú o por lo que decida el bot
emu.addEventCallback(function()
  local input = {}
  local playing = read8(A.game_state) == STATE_PLAY
  if MENU_SCRIPT[frame] then
    input[MENU_SCRIPT[frame]] = true
  elseif mode == "perfect" and playing and not pause_frame and read16(A.song_frame) == PAUSE_AT then
    input.start = true                    -- pausar
    pause_frame = frame
  elseif pause_frame and frame == pause_frame + PAUSE_FRAMES then
    input.start = true                    -- continuar
    resume_frame = frame
  elseif mode == "perfect" and playing and read8(A.paused) == 0 then
    -- Tras leer el control, el juego hará song_frame + 1 y luego juzgará
    local next_frame = read16(A.song_frame) + 1
    for lane = 0, 4 do
      local ptr = read8(A.lane_ptr_lo + lane) + read8(A.lane_ptr_hi + lane) * 256
      if read16(ptr) ~= 0xFFFF and read16(ptr + 2) == next_frame then
        input[LANE_KEYS[lane + 1]] = true
      end
    end
  end
  emu.setInput(input, 0)
end, emu.eventType.inputPolled)

-- Último valor escrito en el registro de volumen del instrumento en cada
-- cuadro. Si el jugador está silenciado, apply_mute lo escribe después del motor.
local last_volume = nil
emu.addMemoryCallback(function(address, value)
  last_volume = value
end, emu.callbackType.write, MUTE_REG[instrument], MUTE_REG[instrument])

local chart = nil
local triggers, trigger_count = {}, 0
local prev_counter = 0
local unmuted_frames = 0
local results_frames = 0
local mid_screenshot_frame = nil

local function finish()
  local hits, exp_score = expected(chart)
  local score = digits(A.score_digits, 6)
  local combo = digits(A.combo_digits, 3)
  local notes_hit, notes_total = read16(A.notes_hit), read16(A.notes_total)
  local max_combo, percent, stars = read16(A.max_combo), read8(A.percent), read8(A.stars)

  -- Sincronía: notas del chart sin un disparo del motor en su mismo cuadro
  local off_sync, offsets = 0, {}
  for _, n in ipairs(chart) do
    if not triggers[n.frame] then
      off_sync = off_sync + 1
      for d = -3, 3 do
        if triggers[n.frame + d] then offsets[d] = (offsets[d] or 0) + 1 break end
      end
    end
  end
  local offset_text = {}
  for d, count in pairs(offsets) do offset_text[#offset_text + 1] = string.format("%+d:%d", d, count) end

  local ok = off_sync == 0 and trigger_count >= #chart and notes_total == hits
  if mode == "perfect" then
    ok = ok and score == exp_score and combo == math.min(hits, 999) and notes_hit == hits
         and max_combo == hits and percent == 100 and stars == 5 and resume_frame ~= nil
  else
    ok = ok and score == 0 and combo == 0 and notes_hit == 0 and percent == 0 and stars == 0
         and unmuted_frames == 0
  end
  write_file("resultado.txt", string.format(
    "modo=%s instrumento=%d notas=%d/%d puntaje=%d (esperado %s) combo_max=%d precision=%d%% estrellas=%d " ..
    "disparos=%d desfasadas=%d [%s] sin_silenciar=%d -> %s\n",
    mode, instrument, notes_hit, notes_total, score, mode == "perfect" and tostring(exp_score) or "0", max_combo,
    percent, stars, trigger_count, off_sync, table.concat(offset_text, " "), unmuted_frames,
    ok and "OK" or "FALLA"))
  emu.stop(ok and 0 or 1)
end

emu.addEventCallback(function()
  frame = frame + 1
  if SCREENSHOTS[frame] then write_file(SCREENSHOTS[frame], emu.takeScreenshot()) end

  local state = read8(A.game_state)
  if state == STATE_PLAY then
    if not chart then
      chart = read_chart()
      mid_screenshot_frame = frame + 2000
    end
    local song_frame = read16(A.song_frame)

    -- El contador del "ecualizador" del motor salta a 9 en cada nota nueva
    -- (un contador por canal: 0 = pulso 1, 1 = pulso 2, 2 = triángulo)
    local counter = read8(A.famistudio_chn_note_counter + instrument)
    if counter > prev_counter then
      triggers[song_frame] = true
      trigger_count = trigger_count + 1
    end
    prev_counter = counter

    -- Sin tocar nada, desde que pasa la primera nota el instrumento debe estar callado
    if mode == "idle" and song_frame > chart[1].frame + 7 and song_frame < chart[#chart].frame
       and last_volume ~= MUTE_VALUE[instrument] then
      unmuted_frames = unmuted_frames + 1
    end
    if frame == mid_screenshot_frame then write_file("captura_juego.png", emu.takeScreenshot()) end
    if pause_frame and frame == pause_frame + 30 then write_file("captura_pausa.png", emu.takeScreenshot()) end
  elseif state == STATE_RESULTS and chart then
    results_frames = results_frames + 1
    if results_frames == 10 then
      write_file("captura_resultados.png", emu.takeScreenshot())
      finish()
    end
  end
  last_volume = nil

  if frame == TIMEOUT then
    write_file("resultado.txt", string.format("modo=%s: no llegó a resultados (estado %d) -> FALLA\n", mode, state))
    emu.stop(1)
  end
end, emu.eventType.endFrame)
