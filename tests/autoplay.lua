-- =============================================================================
-- autoplay.lua - Prueba automática para el modo --testrunner de Mesen 2
--
-- Un bot lee de la RAM cuál es la siguiente nota de cada carril y presiona el
-- botón justo en el cuadro correcto. Al terminar revisa:
--   - puntaje y combo contra lo que debería dar el chart
--   - sincronía: cada nota del chart debe caer en el mismo cuadro en que el
--     motor de sonido dispara una nota en el canal del jugador
-- y sale con código 0 (bien) o 1 (falla).
--
-- Variables de entorno:
--   AUTOPLAY_MODE = perfect (default) | idle (no presiona nada: todo debe fallar)
--   TEST_OUT      = carpeta donde dejar resultado.txt y capturas .png
--
-- Requiere que Mesen tenga habilitado "AllowIoOsAccess" (escribir archivos) y
-- que build/nesband.dbg esté junto a la ROM (para encontrar las variables).
-- =============================================================================

local mode = os.getenv("AUTOPLAY_MODE") or "perfect"
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

local A_SONG_FRAME   = label("song_frame")
local A_LANE_LO      = label("lane_ptr_lo")
local A_LANE_HI      = label("lane_ptr_hi")
local A_SCORE        = label("score_digits")
local A_COMBO        = label("combo_digits")
local A_CHART_START  = label("chart_start")
local A_NOTE_COUNTER = label("famistudio_chn_note_counter")

local CHART_ENTRY = 5
local LANE_KEYS  = { "left", "down", "right", "b", "a" }
local SCREENSHOT_FRAMES = { [400] = "captura_inicio.png", [2000] = "captura_medio.png" }
local END_FRAME  = 4900   -- después de que termina la canción

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
  local p = read16(A_CHART_START)
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

-- Mesen pide el estado del control justo cuando el juego lo lee: ahí lo
-- reemplazamos por lo que decida el bot
emu.addEventCallback(function()
  -- Tras leer el control, el juego hará song_frame + 1 y luego juzgará
  local next_frame = read16(A_SONG_FRAME) + 1
  local input = {}
  if mode == "perfect" then
    for lane = 0, 4 do
      local ptr = read8(A_LANE_LO + lane) + read8(A_LANE_HI + lane) * 256
      if read16(ptr) ~= 0xFFFF and read16(ptr + 2) == next_frame then
        input[LANE_KEYS[lane + 1]] = true
      end
    end
  end
  emu.setInput(input, 0)
end, emu.eventType.inputPolled)

-- Cuadros (song_frame) en que el motor disparó una nota en el canal del jugador.
-- El contador del "ecualizador" del motor salta a 9 en cada nota nueva.
local triggers = {}
local trigger_count = 0
local prev_counter = 0
local frame = 0

-- Último valor escrito en $4000 (volumen del pulso 1) en cada cuadro. Si el
-- jugador está silenciado, apply_mute escribe $30 después del motor.
local last_pulse1_vol = nil
local unmuted_frames = 0
emu.addMemoryCallback(function(address, value)
  last_pulse1_vol = value
end, emu.callbackType.write, 0x4000, 0x4000)

local first_note_frame, song_end = nil, nil

emu.addEventCallback(function()
  frame = frame + 1

  -- Para el cuadro 10 el juego ya inicializó el chart
  if frame == 10 then
    local chart = read_chart()
    first_note_frame = chart[1].frame
    song_end = chart[#chart].frame
  end

  local counter = read8(A_NOTE_COUNTER + 0)   -- canal 0 = pulso 1 (guitarra)
  local song_frame = read16(A_SONG_FRAME)
  if counter > prev_counter then
    triggers[song_frame] = true
    trigger_count = trigger_count + 1
  end
  prev_counter = counter

  -- Sin tocar nada, desde que se pasa la primera nota la guitarra debe estar callada
  if mode == "idle" and first_note_frame and song_frame > first_note_frame + 7 and song_frame < song_end
     and last_pulse1_vol ~= 0x30 then
    unmuted_frames = unmuted_frames + 1
  end
  last_pulse1_vol = nil

  if SCREENSHOT_FRAMES[frame] then
    write_file(SCREENSHOT_FRAMES[frame], emu.takeScreenshot())
  end

  if frame == END_FRAME then
    local chart = read_chart()
    local score = digits(A_SCORE, 6)
    local combo = digits(A_COMBO, 3)
    local hits, exp_score = expected(chart)

    -- Sincronía: ¿cuántas notas del chart no tienen un disparo en su cuadro?
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

    local ok = off_sync == 0 and trigger_count >= #chart
    if mode == "perfect" then
      ok = ok and score == exp_score and combo == math.min(hits, 999)
    else
      ok = ok and score == 0 and combo == 0 and unmuted_frames == 0
    end
    write_file("resultado.txt", string.format(
      "modo=%s notas=%d puntaje=%d (esperado %s) combo=%d disparos=%d desfasadas=%d [%s] sin_silenciar=%d -> %s\n",
      mode, hits, score, mode == "perfect" and tostring(exp_score) or "0", combo, trigger_count,
      off_sync, table.concat(offset_text, " "), unmuted_frames, ok and "OK" or "FALLA"))
    emu.stop(ok and 0 or 1)
  end
end, emu.eventType.endFrame)
