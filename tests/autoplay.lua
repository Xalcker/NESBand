-- =============================================================================
-- autoplay.lua - Prueba automática para el modo --testrunner de Mesen 2
--
-- Recorre el juego completo como lo harían una o dos personas:
--   título (Start) -> menú (canción, jugadores, instrumento y experto, Start)
--   -> juego -> resultados
-- Durante el juego, un bot por jugador lee de la RAM cuál es la siguiente nota
-- de cada carril y presiona el botón de su control justo en el cuadro
-- correcto. Al final revisa, por jugador:
--   - puntaje, combo y estadísticas de la pantalla de resultados
--   - sincronía: cada nota del chart debe caer en el mismo cuadro en que el
--     motor de sonido dispara una nota en el canal de ese jugador
--   - silenciado: si no toca nada, su canal queda callado
-- y sale con código 0 (bien) o 1 (falla).
--
-- Variables de entorno:
--   AUTOPLAY_SONG        canción en el menú (desde 0, orden alfabético)
--   AUTOPLAY_MODE        cómo juega el jugador 1:
--                        perfect (default): acierta todo; además pausa a media canción
--                        idle: no toca nada
--                        smash: machaca los 5 botones un cuadro sí y uno no; acierta
--                        muchas notas de pura suerte, pero los golpes al aire deben
--                        romperle el combo todo el tiempo
--   AUTOPLAY_INSTRUMENT  instrumento del jugador 1: 0 guitarra (default), 1 teclado, 2 bajo
--   AUTOPLAY_PLAYERS     1 (default) o 2
--   AUTOPLAY_MODE2       cómo juega el jugador 2 (default: perfect)
--   AUTOPLAY_INSTRUMENT2 instrumento del jugador 2 (default: 2, bajo; debe ser distinto)
--   TEST_OUT             carpeta donde dejar resultado.txt y capturas .png
--
-- Requiere que Mesen tenga habilitado "AllowIoOsAccess" (escribir archivos) y
-- que build/nesband.dbg esté junto a la ROM (para encontrar las variables).
-- =============================================================================

local song = tonumber(os.getenv("AUTOPLAY_SONG") or "0")
local num_players = tonumber(os.getenv("AUTOPLAY_PLAYERS") or "1")
local modes = { os.getenv("AUTOPLAY_MODE") or "perfect", os.getenv("AUTOPLAY_MODE2") or "perfect" }
local instruments = { tonumber(os.getenv("AUTOPLAY_INSTRUMENT") or "0"),
                      tonumber(os.getenv("AUTOPLAY_INSTRUMENT2") or "2") }
local outdir = os.getenv("TEST_OUT") or "."
local mem = emu.memType.nesMemory

local function label(name)
  local a = emu.getLabelAddress(name)
  if a == nil then error("No encontré el símbolo " .. name .. " (¿falta el .dbg?)") end
  return a.address   -- todo lo que leemos está en la RAM interna
end

local function read8(addr) return emu.read(addr, mem, false) end
local function read16(addr) return read8(addr) + read8(addr + 1) * 256 end

-- Lo de cada jugador vive en su copia guardada: player_save + jugador * tamaño
local PSTATE, SAVE = label("pstate"), label("player_save")
local PSTATE_SIZE = label("pstate_end") - PSTATE
local function field(p, name) return SAVE + (p - 1) * PSTATE_SIZE + (label(name) - PSTATE) end

local A_STATE, A_SONG_FRAME, A_PAUSED = label("game_state"), label("song_frame"), label("paused")
local A_COUNTER = label("famistudio_chn_note_counter")
local A_SFX_PTR_HI = label("famistudio_sfx_base_addr") + 2   -- no 0 mientras suena un efecto

local STATE_PLAY, STATE_RESULTS = 2, 3
local CHART_ENTRY, CHART_END = 2, 0xFF
local LANE_KEYS = { "left", "down", "right", "b", "a" }
local TIMEOUT = 15000
local PAUSE_AT, PAUSE_FRAMES = 1500, 90   -- song_frame en que se pausa, y cuánto dura
-- Machacando, el combo más largo posible es el de un solo golpe (las notas que
-- caigan juntas antes del primer carril vacío): nunca más de 5
local NUM_LANES_SMASH_MAX = 5

-- Registro de volumen del canal de cada instrumento, y lo que escribe apply_mute
local MUTE_REG = { [0] = 0x4000, [1] = 0x4004, [2] = 0x4008 }
local MUTE_VALUE = { [0] = 0x30, [1] = 0x30, [2] = 0x80 }

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

-- Guion del menú: {cuadro, control (0/1), botón}, uno cada 4 cuadros.
-- Jugador 1: canción, jugadores, instrumento, dificultad (de medio a experto).
-- Jugador 2: su instrumento (empieza en bajo) y su dificultad.
local MENU_SCRIPT = { [30] = { 0, "start" } }
local steps = {}
local function add(port, button, times) for _ = 1, times do steps[#steps + 1] = { port, button } end end
add(0, "right", song)
add(0, "down", 1)
add(0, "right", num_players - 1)
add(0, "down", 1)
add(0, "right", instruments[1])
add(0, "down", 1)
add(0, "right", 2)
if num_players == 2 then
  -- Del bajo (2) al instrumento pedido: cada pulsación avanza al siguiente
  -- instrumento válido, saltando batería (3, sin chart) y el del jugador 1
  local pos, presses = 2, 0
  while pos ~= instruments[2] do
    repeat pos = (pos + 1) % 4 until pos ~= 3 and pos ~= instruments[1]
    presses = presses + 1
  end
  add(1, "right", presses)
  add(1, "down", 1)
  add(1, "right", 2)
end
for i, step in ipairs(steps) do MENU_SCRIPT[50 + i * 4] = step end
local menu_done = 50 + #steps * 4
MENU_SCRIPT[menu_done + 12] = { 0, "start" }
local SCREENSHOTS = { [25] = "captura_titulo.png", [menu_done + 8] = "captura_menu.png" }

-- Notas del chart de un jugador: lista de {frame, mask} (sin rellenos)
local function read_chart(p)
  local notes = {}
  local ptr = read16(field(p, "chart_start"))
  local frame = 0
  while read8(ptr + 1) ~= CHART_END do
    frame = frame + read8(ptr)
    local mask = read8(ptr + 1) & 0x1F
    if mask ~= 0 then notes[#notes + 1] = { frame = frame, mask = mask } end
    ptr = ptr + CHART_ENTRY
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

-- Mesen pide el estado de cada control justo cuando el juego lo lee: ahí lo
-- reemplazamos por el guion del menú o por lo que decida el bot
local function bot_input(p)
  local input = {}
  local playing = read8(A_STATE) == STATE_PLAY
  local script = MENU_SCRIPT[frame]
  if script and script[1] == p - 1 then
    input[script[2]] = true
  elseif p == 1 and modes[1] == "perfect" and playing and not pause_frame
         and read16(A_SONG_FRAME) == PAUSE_AT then
    input.start = true                    -- pausar
    pause_frame = frame
  elseif p == 1 and pause_frame and frame == pause_frame + PAUSE_FRAMES then
    input.start = true                    -- continuar
    resume_frame = frame
  elseif p <= num_players and modes[p] == "smash" and playing and frame % 2 == 0 then
    for _, key in ipairs(LANE_KEYS) do input[key] = true end
  elseif p <= num_players and modes[p] == "perfect" and playing and read8(A_PAUSED) == 0 then
    -- Tras leer el control, el juego hará song_frame + 1 y luego juzgará
    local next_frame = read16(A_SONG_FRAME) + 1
    for lane = 0, 4 do
      local ptr = read8(field(p, "lane_ptr_lo") + lane) + read8(field(p, "lane_ptr_hi") + lane) * 256
      local lane_frame = read8(field(p, "lane_frame_lo") + lane) + read8(field(p, "lane_frame_hi") + lane) * 256
      if read8(ptr + 1) ~= CHART_END and lane_frame == next_frame then
        input[LANE_KEYS[lane + 1]] = true
      end
    end
  end
  return input
end

-- Ojo: en Mesen 2.1 el control va en el tercer argumento: setInput(botones, 0, control).
-- Además, en la configuración de Mesen el puerto 2 debe tener un control
-- conectado (Nes.Port2.Type = NesController).
emu.addEventCallback(function()
  emu.setInput(bot_input(1), 0, 0)
  emu.setInput(bot_input(2), 0, 1)
end, emu.eventType.inputPolled)

-- Último valor escrito en el registro de volumen de cada jugador en cada
-- cuadro. Si está silenciado, apply_mute lo escribe después del motor.
local last_volume = {}
for p = 1, num_players do
  emu.addMemoryCallback(function(address, value)
    last_volume[p] = value
  end, emu.callbackType.write, MUTE_REG[instruments[p]], MUTE_REG[instruments[p]])
end

local charts = nil
local triggers, trigger_count, prev_counter, unmuted = {}, {}, {}, {}
for p = 1, num_players do triggers[p], trigger_count[p], prev_counter[p], unmuted[p] = {}, 0, 0, 0 end
local results_frames = 0
local mid_screenshot_frame = nil

local function check_player(p)
  local chart = charts[p]
  local hits, exp_score = expected(chart)
  local score = digits(field(p, "score_digits"), 6)
  local combo = digits(field(p, "combo_digits"), 3)
  local notes_hit, notes_total = read16(field(p, "notes_hit")), read16(field(p, "notes_total"))
  local max_combo, percent, stars = read16(field(p, "max_combo")), read8(field(p, "percent")), read8(field(p, "stars"))

  -- Sincronía: notas del chart sin un disparo del motor en su mismo cuadro
  local off_sync, off_frames = 0, {}
  for _, n in ipairs(chart) do
    if not triggers[p][n.frame] then
      off_sync = off_sync + 1
      if #off_frames < 5 then off_frames[#off_frames + 1] = tostring(n.frame) end
    end
  end

  local ok = off_sync == 0 and trigger_count[p] >= #chart and notes_total == hits
  if modes[p] == "perfect" then
    ok = ok and score == exp_score and combo == math.min(hits, 999) and notes_hit == hits
         and max_combo == hits and percent == 100 and stars == 5
    if p == 1 then ok = ok and resume_frame ~= nil end
  elseif modes[p] == "smash" then
    -- Acierta notas de suerte, pero cada golpe al aire rompe el combo, y
    -- las estrellas (que salen del puntaje) se quedan abajo
    ok = ok and notes_hit > 0 and max_combo <= NUM_LANES_SMASH_MAX and stars <= 2
  else
    ok = ok and score == 0 and combo == 0 and notes_hit == 0 and percent == 0 and stars == 0
         and unmuted[p] == 0
  end
  local text = string.format(
    "J%d %s inst=%d notas=%d/%d puntaje=%d (esperado %s) combo_max=%d precision=%d%% estrellas=%d " ..
    "disparos=%d desfasadas=%d [%s] sin_silenciar=%d",
    p, modes[p], instruments[p], notes_hit, notes_total, score,
    modes[p] == "perfect" and tostring(exp_score) or "0", max_combo, percent, stars,
    trigger_count[p], off_sync, table.concat(off_frames, " "), unmuted[p])
  return ok, text
end

-- Sonido fuera del juego: música en el título y efectos en el menú y al empezar
local title_notes, prev_title_counters = 0, { 0, 0, 0, 0 }
local sfx_menu, sfx_play = false, false

local function finish()
  local all_ok, lines = true, {}
  local sound_ok = title_notes > 0 and sfx_menu and sfx_play
  all_ok = sound_ok
  lines[#lines + 1] = string.format("titulo: %d notas, efecto en menu=%s al empezar=%s",
                                    title_notes, tostring(sfx_menu), tostring(sfx_play))
  for p = 1, num_players do
    local ok, text = check_player(p)
    all_ok = all_ok and ok
    lines[#lines + 1] = text
  end
  write_file("resultado.txt", string.format("cancion=%d %s -> %s\n", song, table.concat(lines, " | "),
                                            all_ok and "OK" or "FALLA"))
  emu.stop(all_ok and 0 or 1)
end

emu.addEventCallback(function()
  frame = frame + 1
  if SCREENSHOTS[frame] then write_file(SCREENSHOTS[frame], emu.takeScreenshot()) end

  local state = read8(A_STATE)
  if state == 0 then          -- título: ¿suena la música?
    for ch = 0, 3 do
      local c = read8(A_COUNTER + ch)
      if c > prev_title_counters[ch + 1] then title_notes = title_notes + 1 end
      prev_title_counters[ch + 1] = c
    end
  elseif state == 1 and frame > 50 and read8(A_SFX_PTR_HI) ~= 0 then
    sfx_menu = true           -- menú, después de que el guion empezó a mover cosas
  elseif state == STATE_PLAY and read16(A_SONG_FRAME) < 30 and read8(A_SFX_PTR_HI) ~= 0 then
    sfx_play = true
  end
  -- enter_play tarda varios cuadros (con la pantalla apagada) en preparar a
  -- los jugadores: los charts se leen cuando la canción ya está corriendo
  if state == STATE_PLAY and read16(A_SONG_FRAME) > 0 then
    if not charts then
      charts = {}
      for p = 1, num_players do charts[p] = read_chart(p) end
      mid_screenshot_frame = frame + 2000
    end
    local song_frame = read16(A_SONG_FRAME)
    for p = 1, num_players do
      -- El contador del "ecualizador" del motor salta a 9 en cada nota nueva
      -- (un contador por canal: 0 = pulso 1, 1 = pulso 2, 2 = triángulo)
      local counter = read8(A_COUNTER + instruments[p])
      if counter > prev_counter[p] then
        triggers[p][song_frame] = true
        trigger_count[p] = trigger_count[p] + 1
      end
      prev_counter[p] = counter

      -- Sin tocar nada, desde que pasa su primera nota el instrumento debe estar
      -- callado. No cuentan la pausa (calla el motor, con otro valor) ni los
      -- cuadros sin escritura al canal (al continuar no se avanza el motor).
      local chart = charts[p]
      if modes[p] == "idle" and song_frame > chart[1].frame + 7 and song_frame < chart[#chart].frame
         and read8(A_PAUSED) == 0 and last_volume[p] ~= nil and last_volume[p] ~= MUTE_VALUE[instruments[p]] then
        unmuted[p] = unmuted[p] + 1
      end
      last_volume[p] = nil
    end
    if frame == mid_screenshot_frame then write_file("captura_juego.png", emu.takeScreenshot()) end
    if pause_frame and frame == pause_frame + 30 then write_file("captura_pausa.png", emu.takeScreenshot()) end
  elseif state == STATE_RESULTS and charts then
    results_frames = results_frames + 1
    if results_frames == 10 then
      write_file("captura_resultados.png", emu.takeScreenshot())
      finish()
    end
  end

  if frame == TIMEOUT then
    write_file("resultado.txt", string.format("cancion=%d: no llegó a resultados (estado %d) -> FALLA\n", song, state))
    emu.stop(1)
  end
end, emu.eventType.endFrame)
