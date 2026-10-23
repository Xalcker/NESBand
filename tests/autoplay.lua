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
--                        idle: no toca nada (con "sin fallo": la canción llega al final)
--                        fail: no toca nada y juega CON fallo: la vida se acaba y pierde
--                        smash: machaca los 5 botones un cuadro sí y uno no; acierta
--                        muchas notas de pura suerte, pero los golpes al aire deben
--                        romperle el combo todo el tiempo
--   AUTOPLAY_INSTRUMENT  instrumento del jugador 1: 0 guitarra (default), 1 teclado, 2 bajo
--   AUTOPLAY_PLAYERS     1 (default) o 2
--   AUTOPLAY_DIFFICULTY  dificultad del jugador 1: 0 fácil .. 3 experto (default)
--   AUTOPLAY_DIFFICULTY2 dificultad del jugador 2 (default: la misma). La autopista
--                        va a la velocidad de la más alta de los dos.
--   AUTOPLAY_MODE2       cómo juega el jugador 2 (default: perfect)
--   AUTOPLAY_INSTRUMENT2 instrumento del jugador 2 (default: 2, bajo; debe ser distinto)
--   AUTOPLAY_STAR        1 = los jugadores perfectos activan el poder estelar (Select) en
--                        cuanto la barra llega a la mitad; 0 (default) = nunca lo activan
--   AUTOPLAY_RECORD      0 (default); 1 = escribe iniciales y comprueba que el récord se guardó;
--                        2 = (con el .sav de la corrida 1) el récord ya existía y no hay uno nuevo
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
local difficulty = tonumber(os.getenv("AUTOPLAY_DIFFICULTY") or "3")   -- 0 fácil .. 3 experto
local difficulty2 = tonumber(os.getenv("AUTOPLAY_DIFFICULTY2") or tostring(difficulty))
local use_star = os.getenv("AUTOPLAY_STAR") == "1"
local STAR_MAX, STAR_PHRASE, STAR_MIN = 80, 20, 40       -- como en main.s
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
local difficulty_presses = (difficulty - 1) % 4      -- desde medio (1), dando la vuelta
add(0, "right", difficulty_presses)
-- Sin fallo (último renglón): para los modos que no tocan o machacan, así la canción
-- llega hasta el final como antes. Con "fail" y "perfect" se juega con fallo.
local function wants_no_fail(p) return modes[p] == "idle" or modes[p] == "smash" end
add(0, "down", 1)
if wants_no_fail(1) then add(0, "right", 1) end
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
  add(1, "right", (difficulty2 - 1) % 4)
  add(1, "down", 1)
  if wants_no_fail(2) then add(1, "right", 1) end
end
for i, step in ipairs(steps) do MENU_SCRIPT[50 + i * 4] = step end
local menu_done = 50 + #steps * 4
MENU_SCRIPT[menu_done + 12] = { 0, "start" }
local SCREENSHOTS = { [25] = "captura_titulo.png", [menu_done + 8] = "captura_menu.png" }

-- Notas del chart de un jugador: lista de {frame, mask} (sin rellenos ni fines de
-- cola), y sus notas sostenidas: lista de {lane, first, last} (cuadro de la nota
-- y cuadro en que termina su cola)
local CHART_SUSTAIN, CHART_RELEASE = 0x40, 0x80
local HOLD_POINTS, HOLD_TICK = 10, 8
local CHART_STAR = 0x20
local function read_chart(p)
  local notes, holds, pending = {}, {}, {}
  local star_runs, prev_star = 0, false
  local ptr = read16(field(p, "chart_start"))
  local frame = 0
  while read8(ptr + 1) ~= CHART_END do
    frame = frame + read8(ptr)
    local raw = read8(ptr + 1)
    local mask = raw & 0x1F
    if raw & CHART_RELEASE ~= 0 then
      for lane = 0, 4 do
        if (mask >> lane) & 1 == 1 and pending[lane] then
          holds[#holds + 1] = { lane = lane, first = pending[lane], last = frame }
          pending[lane] = nil
        end
      end
    elseif mask ~= 0 then
      local star = raw & CHART_STAR ~= 0           -- frases estelares: rachas de notas con la marca
      notes[#notes + 1] = { frame = frame, mask = mask, star = star }
      if star and not prev_star then star_runs = star_runs + 1 end
      prev_star = star
      if raw & CHART_SUSTAIN ~= 0 then
        for lane = 0, 4 do
          if (mask >> lane) & 1 == 1 then pending[lane] = frame end
        end
      end
    end
    ptr = ptr + CHART_ENTRY
  end
  return notes, holds, star_runs
end

-- Puntaje esperado si se aciertan todas y se sostienen las colas hasta el final
-- (mismas reglas que gameplay.s: 10 puntos cada 8 cuadros mientras se sostiene)
local function expected(chart, holds)
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
  for _, h in ipairs(holds) do
    for f = h.first, h.last - 1 do
      if f % HOLD_TICK == 0 then score = score + HOLD_POINTS end
    end
  end
  return hits, score
end

local frame = 0
local pause_frame, resume_frame = nil, nil
local rec_mode = os.getenv("AUTOPLAY_RECORD") or "0"   -- ver "Pruebas de récords" más abajo
local rec_before = nil                                   -- (modo 2) el récord que ya había al encender
local eval_ok, eval_lines, eval_frame = nil, nil, nil    -- resultado de las comprobaciones, y cuándo se hicieron
local RECORD_STEPS = { [10] = "start", [30] = "down", [50] = "start" }    -- modo 1: tras los resultados
local RECORD_STEPS_2 = { [10] = "start" }                                   -- modo 2
local STATE_MENU = 1
local holds = {}     -- por jugador: sus notas sostenidas (se leen junto con el chart)
local star_runs = {}    -- por jugador: cuántas frases estelares tiene su chart
local star_shot_frame = nil   -- cuadro de la canción en que se captura una gema estelar en pantalla
local star_seen = {}    -- por jugador: ¿se vio el poder estelar activo en algún cuadro?
local pause_at = PAUSE_AT   -- se recorre si cae en medio de una nota sostenida (al pausar se sueltan los botones)

-- Mesen pide el estado de cada control justo cuando el juego lo lee: ahí lo
-- reemplazamos por el guion del menú o por lo que decida el bot
local function bot_input(p)
  local input = {}
  local playing = read8(A_STATE) == STATE_PLAY
  local script = MENU_SCRIPT[frame]
  if script and script[1] == p - 1 then
    input[script[2]] = true
  elseif p == 1 and eval_frame then       -- flujo del récord, tras los resultados
    local key = (rec_mode == "1" and RECORD_STEPS or RECORD_STEPS_2)[frame - eval_frame]
    if key then input[key] = true end
  elseif p == 1 and modes[1] == "perfect" and playing and not pause_frame
         and read16(A_SONG_FRAME) == pause_at then
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
    -- Poder estelar: Select en cuanto la barra llega a la mitad
    if use_star and read8(field(p, "star_active")) == 0 and read8(field(p, "star_energy")) >= STAR_MIN then
      input.select = true
    end
    -- Notas sostenidas: mantiene el botón desde la nota hasta el fin de su cola
    for _, h in ipairs(holds[p] or {}) do
      if next_frame >= h.first and next_frame < h.last then input[LANE_KEYS[h.lane + 1]] = true end
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
local results_at = 0     -- song_frame al llegar a los resultados (para ver si la canción terminó antes)
local mid_screenshot_frame = nil

local function check_player(p)
  local chart = charts[p]
  local hits, exp_score = expected(chart, holds[p])
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

  local failed, no_fail = read8(field(p, "failed")), read8(field(p, "no_fail"))
  -- Récord nuevo: solo un jugador perfecto con el .sav vacío (en el modo 2, ya estaba el mismo puntaje)
  local new_record = read8(field(p, "new_record"))
  local expect_record = (modes[p] == "perfect" and rec_mode ~= "2") and 1 or 0
  local ok
  if modes[p] == "fail" then
    -- Quien pierde deja de jugar y su canción puede terminar antes: no se exige sincronía completa
    ok = notes_total == hits
  else
    ok = off_sync == 0 and trigger_count[p] >= #chart and notes_total == hits
  end
  if modes[p] == "perfect" then
    ok = ok and failed == 0 and no_fail == 0     -- un jugador perfecto no pierde
    -- Sin activar el poder estelar, el puntaje es exacto y la barra termina con 25% por frase
    -- (hasta llenarse). Activándolo, el puntaje sube pero a lo más al doble (las estrellas no cambian).
    local score_ok, star_ok
    if use_star then
      score_ok = score <= 2 * exp_score and (star_runs[p] < 2 or (score > exp_score and star_seen[p]))
      star_ok = true
    else
      score_ok = score == exp_score
      star_ok = read8(field(p, "star_energy")) == math.min(STAR_MAX, STAR_PHRASE * star_runs[p])
                and read8(field(p, "star_active")) == 0
    end
    ok = ok and score_ok and star_ok and combo == math.min(hits, 999) and notes_hit == hits
         and max_combo == hits and percent == 100 and stars == 5
    if p == 1 then ok = ok and resume_frame ~= nil end
  elseif modes[p] == "smash" then
    -- Acierta notas de suerte, pero cada golpe al aire rompe el combo, y
    -- las estrellas (que salen del puntaje) se quedan abajo
    ok = ok and notes_hit > 0 and max_combo <= NUM_LANES_SMASH_MAX and stars <= 2
         and failed == 0 and no_fail == 1
  elseif modes[p] == "fail" then
    -- Sin tocar nada y con fallo: la vida se acaba, el instrumento queda callado y, si es el
    -- único jugador, la canción termina antes de su última nota
    ok = ok and failed == 1 and no_fail == 0 and score == 0 and notes_hit == 0 and unmuted[p] == 0
    if num_players == 1 then ok = ok and results_at < chart[#chart].frame end
  else
    ok = ok and score == 0 and combo == 0 and notes_hit == 0 and percent == 0 and stars == 0
         and unmuted[p] == 0 and failed == 0 and no_fail == 1
  end
  local text = string.format(
    "J%d %s inst=%d notas=%d/%d puntaje=%d (esperado %s) combo_max=%d precision=%d%% estrellas=%d " ..
    "disparos=%d desfasadas=%d [%s] sin_silenciar=%d perdio=%d sin_fallo=%d record_nuevo=%d",
    p, modes[p], instruments[p], notes_hit, notes_total, score,
    modes[p] == "perfect" and tostring(exp_score) or "0", max_combo, percent, stars,
    trigger_count[p], off_sync, table.concat(off_frames, " "), unmuted[p], failed, no_fail, new_record)
  return ok and new_record == expect_record, text
end

-- Sonido fuera del juego: música en el título y efectos en el menú y al empezar
local title_notes, prev_title_counters = 0, { 0, 0, 0, 0 }
local sfx_menu, sfx_play = false, false

-- Récords guardados (RAM con batería, $6000): firma, suma, y 250 registros de 13 bytes
local REC_TABLE, REC_SIZE, REC_MAX = 0x6008, 13, 250
local function find_record(key)
  for i = 0, REC_MAX - 1 do
    local a = REC_TABLE + i * REC_SIZE
    if read8(a + 2) == key then return a end
  end
  return nil
end
local record_key = instruments[1] * 4 + difficulty

local function evaluate()
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
  return all_ok, lines
end

local function finalize(all_ok, lines)
  write_file("resultado.txt", string.format("cancion=%d %s -> %s\n", song, table.concat(lines, " | "),
                                            all_ok and "OK" or "FALLA"))
  emu.stop(all_ok and 0 or 1)
end

-- Pruebas de récords (AUTOPLAY_RECORD):
--   1: tras los resultados, entra a escribir las iniciales: baja la primera letra (A -> Z),
--      confirma y comprueba que el récord quedó en la RAM con batería
--   2: (sin borrar el .sav de la corrida 1) el récord ya estaba al encender, y como el
--      puntaje es igual, no hay récord nuevo y Start regresa directo al menú
local function record_flow(frames_since)
  local state = read8(A_STATE)
  if rec_mode == "1" and frames_since == 40 then write_file("captura_iniciales.png", emu.takeScreenshot()) end
  if rec_mode == "1" and frames_since == 80 then
    local a = find_record(record_key)
    local ok = state == STATE_MENU and a ~= nil
    if ok then
      ok = digits(a + 3, 6) == digits(field(1, "score_digits"), 6)
           and read8(a + 9) == string.byte("Z") and read8(a + 10) == string.byte("A")
           and read8(a + 11) == string.byte("A") and read8(a + 12) == read8(field(1, "stars"))
           and read8(0x6000) == string.byte("N")
    end
    local lines = eval_lines
    lines[#lines + 1] = "record guardado=" .. tostring(ok)
    finalize(eval_ok and ok, lines)
  elseif rec_mode == "2" and frames_since == 40 then
    local lines = eval_lines
    local ok = state == STATE_MENU and rec_before ~= nil
    lines[#lines + 1] = "record previo=" .. tostring(rec_before ~= nil) .. " directo al menu=" .. tostring(state == STATE_MENU)
    finalize(eval_ok and ok, lines)
  end
end

local function finish()
  local all_ok, lines = evaluate()
  if rec_mode == "0" then
    finalize(all_ok, lines)
  else
    eval_ok, eval_lines, eval_frame = all_ok, lines, frame     -- seguimos jugando el flujo del récord
  end
end

emu.addEventCallback(function()
  frame = frame + 1
  if SCREENSHOTS[frame] then write_file(SCREENSHOTS[frame], emu.takeScreenshot()) end

  local state = read8(A_STATE)
  if rec_mode == "2" and frame == 100 then rec_before = find_record(record_key) end
  if eval_frame then record_flow(frame - eval_frame) end
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
      for p = 1, num_players do charts[p], holds[p], star_runs[p] = read_chart(p) end
      for i, n in ipairs(charts[1]) do          -- captura con el rayo de la primera frase estelar completa
        if n.star and not (charts[1][i + 1] and charts[1][i + 1].star) then
          star_shot_frame = n.frame + 3
          break
        end
      end
      local busy = true
      while busy do
        busy = false
        for p = 1, num_players do
          for _, h in ipairs(holds[p]) do
            if pause_at >= h.first - 2 and pause_at <= h.last + 2 then busy = true; pause_at = pause_at + 1 end
          end
        end
      end
      mid_screenshot_frame = frame + 2000
    end
    local song_frame = read16(A_SONG_FRAME)
    for p = 1, num_players do
      if read8(field(p, "star_active")) == 1 then star_seen[p] = true end
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
      if (modes[p] == "idle" or modes[p] == "fail") and song_frame > chart[1].frame + 7 and song_frame < chart[#chart].frame
         and read8(A_PAUSED) == 0 and last_volume[p] ~= nil and last_volume[p] ~= MUTE_VALUE[instruments[p]] then
        unmuted[p] = unmuted[p] + 1
      end
      last_volume[p] = nil
    end
    if frame == mid_screenshot_frame then write_file("captura_juego.png", emu.takeScreenshot()) end
    if song_frame == star_shot_frame then write_file("captura_estrella.png", emu.takeScreenshot()) end
    if pause_frame and frame == pause_frame + 30 then write_file("captura_pausa.png", emu.takeScreenshot()) end
  elseif state == STATE_RESULTS and charts then
    results_frames = results_frames + 1
    if results_frames == 1 then results_at = read16(A_SONG_FRAME) end
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
