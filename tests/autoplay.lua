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
--                        human90 / human50: jugador "humano" que acierta ~90% / ~45% de las notas, con
--                        los errores en rachas y golpes al aire (semilla fija). El de 90% debe terminar
--                        la canción con fallo activado y el de 45% debe perder (balance de la vida, #7)
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
--   AUTOPLAY_COOP        1 = modo Co-Op (con 2 jugadores): puntaje, combo, vida y poder estelar de
--                        la banda; el puntaje esperado es el de los dos charts mezclados por cuadro
--   AUTOPLAY_VS          (modo VS, 2 jugadores) quién debe ganar: 1, 2 o 3 = empate; 0 (default) = no se revisa
--   AUTOPLAY_CUT         1 = (VS con fallo) la partida debe cortarse porque un jugador pierde: el otro gana
--                        y no se le exige haber terminado la canción (#8)
--   AUTOPLAY_DOWN        1 = Co-Op: el jugador 2 (sin tocar, con fallo) cae y el 1 sigue hasta el final (#10)
--   AUTOPLAY_REVIVE      1 = además, el jugador 1 lo revive con Select cuando la barra de poder llega a la mitad
--   AUTOPLAY_MIRROR      1 = opción ESPEJO (carriles invertidos; el bot juega igual, el puntaje no cambia) (#6)
--   AUTOPLAY_SPEED       0 = 100% (default), 1 = 75%, 2 = 50% (la canción y las notas avanzan más lento), 3 = 125% (más rápido)
--   AUTOPLAY_FALL        0 = AUTO (default), 1-4 = caída de notas como la de fácil .. experto
--   AUTOPLAY_PRACTICE    0 = no (default), 1-3 = bucle hasta 1/4, 1/2 o 3/4 de la canción, 4 = toda: sin fallo,
--                        sin resultados; la prueba termina cuando la canción vuelve a empezar
--   AUTOPLAY_START       0 = el principio (default), 1-3 = la práctica empieza en 1/4, 1/2 o 3/4 de la canción
--                        (#16): se revisa en qué cuadro arranca y que la música cuadre con las notas desde ahí
--   TEST_OUT            carpeta donde dejar resultado.txt y capturas .png
--
-- Requiere que Mesen tenga habilitado "AllowIoOsAccess" (escribir archivos) y
-- que build/nesband.dbg esté junto a la ROM (para encontrar las variables).
-- =============================================================================

local song = tonumber(os.getenv("AUTOPLAY_SONG") or "0")
local num_players = tonumber(os.getenv("AUTOPLAY_PLAYERS") or "1")
local modes = { os.getenv("AUTOPLAY_MODE") or "perfect", os.getenv("AUTOPLAY_MODE2") or "perfect" }
local instruments = { tonumber(os.getenv("AUTOPLAY_INSTRUMENT") or "0"),
                      tonumber(os.getenv("AUTOPLAY_INSTRUMENT2") or "2") }
local has_drums = os.getenv("AUTOPLAY_DRUMS") == "1"   -- la canción tiene chart de batería (instrumento 3): el menú la ofrece
local difficulty = tonumber(os.getenv("AUTOPLAY_DIFFICULTY") or "3")   -- 0 fácil .. 3 experto
local difficulty2 = tonumber(os.getenv("AUTOPLAY_DIFFICULTY2") or tostring(difficulty))
local use_star = os.getenv("AUTOPLAY_STAR") == "1"
local coop = os.getenv("AUTOPLAY_COOP") == "1" and num_players == 2
local vs_expect = tonumber(os.getenv("AUTOPLAY_VS") or "0")
local revive = os.getenv("AUTOPLAY_REVIVE") == "1"   -- Co-Op: el jugador 1 revive al 2 con poder estelar (#10)
local down = revive or os.getenv("AUTOPLAY_DOWN") == "1"   -- Co-Op: el jugador 2 cae y el 1 sigue hasta el final (#10)
local revived, prev_failed2 = 0, 0                -- veces que se revivió al jugador 2
local cut = os.getenv("AUTOPLAY_CUT") == "1"    -- VS: la partida se corta porque el otro jugador pierde (#8)
local opt_mirror = os.getenv("AUTOPLAY_MIRROR") == "1"          -- opciones (#6): ver options.s
local opt_speed = tonumber(os.getenv("AUTOPLAY_SPEED") or "0")
local opt_fall = tonumber(os.getenv("AUTOPLAY_FALL") or "0")
local opt_practice = tonumber(os.getenv("AUTOPLAY_PRACTICE") or "0")
local opt_start = tonumber(os.getenv("AUTOPLAY_START") or "") or 0
local PRACTICE_GRACE = 60       -- como en main.s: las notas de los primeros cuadros de una práctica con inicio se omiten
local any_option = opt_mirror or opt_speed > 0 or opt_fall > 0 or opt_practice > 0
-- ESPEJO de verdad: la batería no se espeja (su bombo, el carril 4, iría al del verde); basta que un jugador la toque
local mirror_on = opt_mirror and not (instruments[1] == 3 or (num_players == 2 and instruments[2] == 3))
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
local A_VS_RESULT = label("vs_result")
-- Cuadros sueltos con el instrumento sonando que se perdonan: en los cuadros más pesados el
-- juego termina su lógica pegado al vblank y el motor de sonido puede escribir justo después
-- de silenciar (un cuadro de 16 ms, que no se oye). Si de verdad no se silencia, son cientos.
local UNMUTED_TOLERANCE = 8   -- (con acordes los cuadros pesados son más; ver #13: 4 cuadros en cv3_aquarius)
local A_NMI_COUNT = label("frame_counter")
local A_SCENE_BANK, A_SCENE_COLOR = label("scene_bank"), label("scene_color")   -- escenario (#4)
local A_SCENE_PHASE, A_SCENE_ON = label("scene_phase"), label("scene_on")
local A_BEAT_FRAMES, A_SONG_PTR = label("beat_frames"), label("song_ptr")
local SONG_BEAT_FRAMES, SONG_FIRST_BEAT = 4, 5                                 -- campos de la ficha de la canción
local prev_nmi, lag_frames = nil, {}
local A_COUNTER = label("famistudio_chn_note_counter")
local A_SFX_PTR_HI = label("famistudio_sfx_base_addr") + 2   -- no 0 mientras suena un efecto

local STATE_PLAY, STATE_RESULTS = 2, 3
local CHART_ENTRY, CHART_END = 2, 0xFF
local LANE_KEYS = { "left", "down", "right", "b", "a" }
local TIMEOUT = 15000 * (opt_speed == 2 and 2 or 1)     -- (a 50% la canción tarda el doble)
local PAUSE_AT, PAUSE_FRAMES = 1500, 90   -- song_frame en que se pausa, y cuánto dura
-- Machacando, el combo más largo posible es el de un solo golpe (las notas que
-- caigan juntas antes del primer carril vacío): nunca más de 5
local NUM_LANES_SMASH_MAX = 5

-- Registro de volumen del canal de cada instrumento, y lo que escribe apply_mute
local MUTE_REG = { [0] = 0x4000, [1] = 0x4004, [2] = 0x4008, [3] = 0x400C }   -- la batería: el ruido
local MUTE_VALUE = { [0] = 0x30, [1] = 0x30, [2] = 0x80, [3] = 0x30 }

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
-- Jugadores: 1 jugador -> 2 jugadores VS -> 2 jugadores Co-Op
add(0, "right", coop and 2 or num_players - 1)
add(0, "down", 1)
-- Lo que el menú hace con los instrumentos (menu.s): al entrar a VS el jugador 2 copia al 1; en
-- Co-Op pasa al siguiente que no sea el del 1; y en VS cada instrumento que elige el 1 lo copia el 2.
-- presses_to: pulsaciones de "derecha" para ir de un instrumento a otro, saltando la batería (3) si la
-- canción no tiene chart de batería (AUTOPLAY_DRUMS=1: sí tiene) y el instrumento `taken` (-1 = ninguno: en VS pueden coincidir).
local function presses_to(from, target, taken)
  local pos, n = from, 0
  while pos ~= target do
    repeat pos = (pos + 1) % 4 until (pos ~= 3 or has_drums) and pos ~= taken
    n = n + 1
    if n > 8 then error("instrumento inalcanzable en el menú") end
  end
  return n
end
local menu_p1, menu_p2 = 0, 2          -- lo que muestra el menú al encender
if num_players == 2 then
  menu_p2 = menu_p1                     -- (pasa por VS)
  if coop then repeat menu_p2 = (menu_p2 + 1) % 4 until (menu_p2 ~= 3 or has_drums) and menu_p2 ~= menu_p1 end
end
add(0, "right", presses_to(menu_p1, instruments[1], coop and menu_p2 or -1))
if num_players == 2 and not coop then menu_p2 = instruments[1] end
add(0, "down", 1)
local difficulty_presses = (difficulty - 1) % 4      -- desde medio (1), dando la vuelta
add(0, "right", difficulty_presses)
-- Sin fallo (último renglón): para los modos que no tocan o machacan, así la canción
-- llega hasta el final como antes. Con "fail" y "perfect" se juega con fallo.
local function wants_no_fail(p) return modes[p] == "idle" or modes[p] == "smash" end
add(0, "down", 1)
if wants_no_fail(1) then add(0, "right", 1) end
if num_players == 2 then
  -- Jugador 2: desde lo que dejó el menú hasta el instrumento pedido. Su dificultad solo se
  -- elige en Co-Op: en VS sigue a la del jugador 1 (ver #9)
  add(1, "right", presses_to(menu_p2, instruments[2], coop and instruments[1] or -1))
  add(1, "down", 1)
  if coop then add(1, "right", (difficulty2 - 1) % 4) end
  add(1, "down", 1)
  if wants_no_fail(2) then add(1, "right", 1) end
end
if any_option then      -- Select abre las opciones: espejo, velocidad, caída de notas y práctica
  add(0, "select", 1)
  add(0, "right", opt_mirror and 1 or 0)
  add(0, "down", 1)
  add(0, "right", opt_speed)
  add(0, "down", 1)
  add(0, "right", opt_fall)
  add(0, "down", 1)
  add(0, "right", opt_practice)
  add(0, "down", 1)
  add(0, "right", opt_start)
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
      -- (en la batería el bit $40 es un platillo, no una cola)
      if raw & CHART_SUSTAIN ~= 0 and instruments[p] ~= 3 then
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
local scene_shots = {}          -- capturas del escenario que ya se tomaron (por banco y por color de luz)
local scene_banks = {}          -- bancos de público que se vieron durante la canción
local scene_lights = {}         -- colores de luz que se vieron (con poder estelar cambian cada tiempo)
local speed_f1, speed_f2 = nil, nil   -- cuadro real en que la canción llegó a su cuadro 200 y al 1200 (para medir la velocidad)
local prev_song_frame, practice_done = nil, false
local practice_first = nil      -- práctica con inicio: song_frame en el primer cuadro con la pantalla encendida
local scene_drift = 0           -- cuadros en que la fase del tiempo del escenario no cuadró con la canción
local scene_behind = false      -- el cuadro anterior la fase iba un cuadro atrás (puede ser solo la muestra)
local star_seen = {}    -- por jugador: ¿se vio el poder estelar activo en algún cuadro?
local pause_at = PAUSE_AT   -- se recorre si cae en medio de una nota sostenida (al pausar se sueltan los botones)

-- Jugador "humano" (modos human90 y human50): acierta una parte de las notas, con los errores
-- en rachas como los de una persona (un estado "bueno" y uno "malo" con distinta precisión) y,
-- a veces, un golpe al aire antes de la nota que se le va. Usa un generador con semilla fija:
-- cada corrida es igual a la anterior. Perfiles: bueno, p(entrar a mala racha), p(salir), malo.
-- (Precisión resultante: human90 ~ 90%, human50 ~ 45%; ver #7.)
local charts = nil     -- (se llena al empezar la canción; más abajo)
local HUMAN = { human90 = { 0.98, 0.04, 0.20, 0.50 }, human50 = { 0.70, 0.10, 0.10, 0.20 } }
local LOOKAHEAD = 20      -- cuadros antes de la nota en que el humano "decide" (y da el golpe al aire)
local human_seed, human_bad, human_plan, human_hit = {}, {}, {}, {}
local function human_random(p)
  human_seed[p] = (human_seed[p] * 1103515245 + 12345) % 2147483648
  return (human_seed[p] // 65536) / 32768.0
end
for p = 1, 2 do human_seed[p], human_bad[p] = 4242 + p, false end

-- Arma de una vez qué botones presiona el humano y en qué cuadro, recorriendo las notas del
-- chart en orden. Presiona en el cuadro de cada nota que "acierta" (como una persona: toca al
-- ritmo aunque una nota anterior se le haya ido, así que si una nota repetida en el mismo
-- carril se le pasa, el siguiente golpe suele caerle a esa) y, en las que falla, a veces da
-- un golpe al aire LOOKAHEAD cuadros antes. human_plan[p][cuadro] = { carril = true }.
local function human_make_plan(p)
  local profile = HUMAN[modes[p]]
  local plan, hit_set = {}, {}
  local function press(frame, lane)
    plan[frame] = plan[frame] or {}
    plan[frame][lane] = true
  end
  for _, n in ipairs(charts[p]) do
    for lane = 0, 4 do
      if (n.mask >> lane) & 1 == 1 then
        if human_bad[p] then
          if human_random(p) < profile[3] then human_bad[p] = false end
        elseif human_random(p) < profile[2] then
          human_bad[p] = true
        end
        if human_random(p) < (human_bad[p] and profile[4] or profile[1]) then
          press(n.frame, lane)
          hit_set[lane .. ":" .. n.frame] = true
        elseif human_random(p) < 0.5 then
          press(n.frame - LOOKAHEAD, lane)
        end
      end
    end
  end
  human_plan[p], human_hit[p] = plan, hit_set
end

-- Devuelve las teclas que el humano presiona en el siguiente cuadro
local function human_input(p, input, next_frame)
  if not charts then return end
  if not human_plan[p] then human_make_plan(p) end
  for lane in pairs(human_plan[p][next_frame] or {}) do input[LANE_KEYS[lane + 1]] = true end
  -- Notas sostenidas: las que acertó, hasta el fin de su cola
  for _, h in ipairs(holds[p] or {}) do
    if human_hit[p][h.lane .. ":" .. h.first] and next_frame >= h.first and next_frame < h.last then
      input[LANE_KEYS[h.lane + 1]] = true
    end
  end
end

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
  elseif p <= num_players and HUMAN[modes[p]] and playing and read8(A_PAUSED) == 0 then
    human_input(p, input, read16(A_SONG_FRAME) + 1)
  elseif p <= num_players and modes[p] == "perfect" and playing and read8(A_PAUSED) == 0 then
    -- Tras leer el control, el juego hará song_frame + 1 y luego juzgará
    local next_frame = read16(A_SONG_FRAME) + 1
    for lane = 0, 4 do
      local ptr = read8(field(p, "lane_ptr_lo") + lane) + read8(field(p, "lane_ptr_hi") + lane) * 256
      local lane_frame = read8(field(p, "lane_frame_lo") + lane) + read8(field(p, "lane_frame_hi") + lane) * 256
      -- (a 125%, de cada 4 cuadros uno avanza dos pasos: el cuadro de en medio nunca se ve, así que se
      -- toca un cuadro antes, que cae dentro de la ventana)
      if read8(ptr + 1) ~= CHART_END and (lane_frame == next_frame or (opt_speed == 3 and lane_frame == next_frame + 1)) then
        input[LANE_KEYS[lane + 1]] = true
      end
    end
    -- Co-Op: si el compañero cayó y la barra llega a la mitad, Select lo revive
    if revive and p == 1 and read8(field(2, "failed")) == 1 and read8(field(1, "star_energy")) >= STAR_MIN then
      input.select = true
    end
    -- Poder estelar: Select en cuanto la barra llega a la mitad
    if use_star and read8(field(p, "star_active")) == 0 and read8(field(p, "star_energy")) >= STAR_MIN then
      input.select = true
    end
    -- Notas sostenidas: mantiene el botón desde la nota hasta el fin de su cola
    for _, h in ipairs(holds[p] or {}) do
      if next_frame >= h.first and next_frame < h.last then
        input[LANE_KEYS[(mirror_on and 4 - h.lane or h.lane) + 1]] = true   -- (el chart dice un carril; con espejo se toca el de enfrente)
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

local prev_dpcm = {}       -- batería: el contador del canal DPCM del cuadro anterior
local triggers, trigger_count, prev_counter, unmuted = {}, {}, {}, {}
for p = 1, num_players do triggers[p], trigger_count[p], prev_counter[p], unmuted[p] = {}, 0, 0, 0 end
local results_frames = 0
local results_at = 0     -- song_frame al llegar a los resultados (para ver si la canción terminó antes)
local mid_screenshot_frame = nil

-- Co-Op: puntaje esperado de la banda. Las notas de los dos se juzgan en el orden en que caen
-- (cuadro, jugador, carril) y comparten un solo combo; las colas suman sus puntos aparte.
local function team_expected()
  local events, score, combo = {}, 0, 0
  for p = 1, num_players do
    for _, n in ipairs(charts[p]) do
      for lane = 0, 4 do
        if (n.mask >> lane) & 1 == 1 then events[#events + 1] = { frame = n.frame, p = p, lane = lane } end
      end
    end
  end
  table.sort(events, function(a, b)
    if a.frame ~= b.frame then return a.frame < b.frame end
    if a.p ~= b.p then return a.p < b.p end
    return a.lane < b.lane
  end)
  for _ = 1, #events do
    combo = math.min(combo + 1, 999)
    score = score + 50 * math.min(combo // 10 + 1, 4)
  end
  for p = 1, num_players do
    for _, h in ipairs(holds[p]) do
      for f = h.first, h.last - 1 do
        if f % HOLD_TICK == 0 then score = score + HOLD_POINTS end
      end
    end
  end
  return #events, score
end

local function check_player(p)
  local chart = charts[p]
  local hits, exp_score = expected(chart, holds[p])
  -- En Co-Op el puntaje, el combo y la barra de poder son de la banda
  local team_hits, team_score, team_runs = hits, exp_score, star_runs[p]
  if coop then
    team_hits, team_score = team_expected()
    team_runs = 0
    for q = 1, num_players do team_runs = team_runs + star_runs[q] end
  end
  local score = digits(field(p, "score_digits"), 6)
  local combo = digits(field(p, "combo_digits"), 3)
  local notes_hit, notes_total = read16(field(p, "notes_hit")), read16(field(p, "notes_total"))
  local max_combo, percent, stars = read16(field(p, "max_combo")), read8(field(p, "percent")), read8(field(p, "stars"))

  -- Sincronía: notas del chart sin un disparo del motor en su mismo cuadro
  local off_sync, off_frames = 0, {}
  for _, n in ipairs(chart) do
    -- (a 125% el motor puede disparar en el cuadro que nunca se ve: se registra en el siguiente)
    if not triggers[p][n.frame] and not (opt_speed == 3 and triggers[p][n.frame + 1]) then
      off_sync = off_sync + 1
      if #off_frames < 5 then off_frames[#off_frames + 1] = tostring(n.frame) end
    end
  end

  local failed, no_fail = read8(field(p, "failed")), read8(field(p, "no_fail"))
  -- Récord nuevo: solo un jugador perfecto con el .sav vacío (en el modo 2, ya estaba el mismo puntaje)
  local new_record = read8(field(p, "new_record"))
  local expect_record = ((modes[p] == "perfect" or modes[p] == "human90") and rec_mode ~= "2") and 1 or 0
  if coop and p == 2 then expect_record = 0 end     -- el récord de la banda es del jugador 1
  if cut or down then expect_record = 0 end         -- una partida cortada, o con un caído, no vale como récord
  if any_option then expect_record = 0 end          -- con opciones (espejo, velocidad, caída, práctica) no hay récord (#6)
  local ok
  if modes[p] == "fail" or modes[p] == "human50" or (cut and modes[p] == "perfect") then
    -- Quien pierde deja de jugar y su canción puede terminar antes: no se exige sincronía completa
    ok = notes_total == hits
  else
    ok = off_sync == 0 and trigger_count[p] >= #chart and notes_total == hits
  end
  if down and modes[p] == "perfect" then
    -- Co-Op con un compañero caído: este sigue y termina la canción, tocando todas sus notas
    -- (el puntaje de la banda ya no es el de la suma exacta: las notas del caído rompieron el combo)
    ok = ok and failed == 0 and no_fail == 0 and notes_hit == hits and percent == 100
         and results_at >= chart[#chart].frame
  elseif cut and modes[p] == "perfect" then
    -- El otro jugador perdió y la partida se cortó: este no perdió y no llegó al final
    ok = ok and failed == 0 and no_fail == 0 and notes_hit > 0 and notes_hit < notes_total
  elseif modes[p] == "perfect" then
    ok = ok and failed == 0 and no_fail == 0     -- un jugador perfecto no pierde
    -- Sin activar el poder estelar, el puntaje es exacto y la barra termina con 25% por frase
    -- (hasta llenarse). Activándolo, el puntaje sube pero a lo más al doble (las estrellas no cambian).
    local score_ok, star_ok
    if use_star then
      score_ok = score <= 2 * team_score and (team_runs < 2 or (score > team_score and (star_seen[1] or star_seen[p])))
      star_ok = true
    else
      score_ok = score == team_score
      if opt_speed == 3 then   -- a 125% el bot toca un cuadro antes en algunos pasos: puede cambiar algún tic de nota sostenida
        score_ok = math.abs(score - team_score) <= HOLD_POINTS * 2 * #holds[p]
      end
      star_ok = read8(field(p, "star_energy")) == math.min(STAR_MAX, STAR_PHRASE * team_runs)
                and read8(field(p, "star_active")) == 0
    end
    ok = ok and score_ok and star_ok and combo == math.min(team_hits, 999) and notes_hit == hits
         and max_combo == team_hits and percent == 100 and stars == 5
    if p == 1 then ok = ok and resume_frame ~= nil end
  elseif modes[p] == "human90" then
    -- Un jugador que acierta ~90% (con los errores en rachas) debe terminar la canción con fallo
    -- activado, pero sin ser perfecto (#7)
    ok = ok and failed == 0 and no_fail == 0 and notes_hit * 100 >= notes_total * 80 and notes_hit < notes_total
         and score > 0
  elseif modes[p] == "human50" then
    -- Uno que acierta menos de la mitad debe perder
    ok = ok and failed == 1 and no_fail == 0
  elseif modes[p] == "smash" then
    -- Acierta notas de suerte, pero cada golpe al aire rompe el combo, y
    -- las estrellas (que salen del puntaje) se quedan abajo
    ok = ok and notes_hit > 0 and max_combo <= NUM_LANES_SMASH_MAX and stars <= 2
         and failed == 0 and no_fail == 1
  elseif modes[p] == "fail" then
    -- Sin tocar nada y con fallo: la vida se acaba, el instrumento queda callado y, si es el
    -- único jugador, la canción termina antes de su última nota
    -- (en Co-Op el puntaje es de la banda, y revivido deja de estar callado hasta su siguiente fallo)
    ok = ok and no_fail == 0 and notes_hit == 0 and (coop or score == 0)
    if revive then
      ok = ok and revived >= 1
    else
      ok = ok and failed == 1 and unmuted[p] <= UNMUTED_TOLERANCE
    end
    if num_players == 1 then ok = ok and results_at < chart[#chart].frame end
  else
    ok = ok and score == 0 and combo == 0 and notes_hit == 0 and percent == 0 and stars == 0
         and unmuted[p] <= UNMUTED_TOLERANCE and failed == 0 and no_fail == 1
  end
  local text = string.format(
    "J%d %s inst=%d notas=%d/%d puntaje=%d (esperado %s) combo_max=%d precision=%d%% estrellas=%d " ..
    "disparos=%d desfasadas=%d [%s] sin_silenciar=%d perdio=%d sin_fallo=%d record_nuevo=%d",
    p, modes[p], instruments[p], notes_hit, notes_total, score,
    modes[p] == "perfect" and tostring(team_score) or "0", max_combo, percent, stars,
    trigger_count[p], off_sync, table.concat(off_frames, " "), unmuted[p], failed, no_fail, new_record)
  -- (con revivir, el compañero puede terminar en pie y entonces sí hay récord de banda)
  return ok and (new_record == expect_record or revive), text
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
  if coop then
    -- Lo compartido debe ser igual en la copia de los dos jugadores
    local same = true
    for _, name in ipairs({ "score_digits", "combo_digits", "star_energy", "stars" }) do
      local n = (name == "score_digits") and 6 or (name == "combo_digits" and 3 or 1)
      if digits(field(1, name), n) ~= digits(field(2, name), n) then same = false end
    end
    all_ok = all_ok and same
    lines[#lines + 1] = "banda compartida=" .. tostring(same)
  end
  if num_players == 2 and not coop then
    -- En VS los dos juegan la misma dificultad: la del jugador 1 (#9)
    local d1, d2 = read8(field(1, "cur_difficulty")), read8(field(2, "cur_difficulty"))
    local same = d1 == difficulty and d2 == difficulty
    all_ok = all_ok and same
    lines[#lines + 1] = string.format("VS misma dificultad=%s (%d, %d)", tostring(same), d1, d2)
  end
  -- Escenario (#4): sigue el tiempo de la canción, el público salta solo con combo, las luces
  -- cambian con el poder estelar y al salir del juego el fondo vuelve a su banco de siempre
  local perfect, other = false, false
  for p = 1, num_players do
    if modes[p] == "perfect" then perfect = true elseif modes[p]:sub(1, 5) == "human" then other = true end
  end
  local scene_ok = scene_drift == 0 and read8(A_SCENE_ON) == 0 and scene_banks[4] == true
  if perfect and not cut then   -- (si la partida se corta al principio, no hay tiempo de animarse)
    scene_ok = scene_ok and scene_banks[6] == true and scene_banks[8] == true   -- brazos arriba y saltos
  elseif not other and not perfect then
    scene_ok = scene_ok and scene_banks[6] == nil and scene_banks[8] == nil     -- sin combo, quieto
  end
  if use_star and perfect then
    local changed = false
    for color in pairs(scene_lights) do
      if color ~= 0x12 and color ~= 0x22 and color ~= 0x30 and color ~= 0x0F then changed = true end
    end
    scene_ok = scene_ok and changed
  end
  all_ok = all_ok and scene_ok
  local banks, lights = {}, {}
  for b in pairs(scene_banks) do banks[#banks + 1] = b end
  for c in pairs(scene_lights) do lights[#lights + 1] = string.format("%02X", c) end
  table.sort(banks); table.sort(lights)
  lines[#lines + 1] = string.format("escenario=%s (desfase %d cuadros, bancos %s, luces %s, scene_on=%d)", tostring(scene_ok), scene_drift,
                                    table.concat(banks, "/"), table.concat(lights, "/"), read8(A_SCENE_ON))
  -- Opciones (#6): sin récord, carriles invertidos, caída y velocidad como se pidieron
  if any_option then
    local ok = read8(field(1, "new_record")) == 0
    if opt_mirror then   -- con la batería el espejo se ignora (mirror_on = 0): los carriles quedan como están
      local cb = label("chart_bit")
      for lane = 0, 4 do
        local want_bit = mirror_on and (1 << (4 - lane)) or (1 << lane)
        if read8(cb + lane) ~= want_bit then ok = false end
      end
    end
    if opt_fall > 0 and read8(label("fpr")) ~= ({ 6, 5, 4, 3 })[opt_fall] then ok = false end
    local ratio = (speed_f1 and speed_f2) and (speed_f2 - speed_f1) / 1000 or nil   -- cuadros reales por cuadro de la canción
    local want = ({ 1, 4 / 3, 2, 0.8 })[opt_speed + 1]
    if not ratio or math.abs(ratio - want) > 0.05 then ok = false end
    all_ok = all_ok and ok
    lines[#lines + 1] = string.format("opciones=%s (reloj x%s, esperado %.2f)", tostring(ok), ratio and string.format("%.2f", ratio) or "?", want)
  end
  if vs_expect ~= 0 then
    local winner = read8(A_VS_RESULT)
    all_ok = all_ok and winner == vs_expect
    lines[#lines + 1] = string.format("VS ganador=%d (esperado %d)", winner, vs_expect)
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
  if state == STATE_PLAY and read16(A_SONG_FRAME) > 0 and read8(label("scene_on")) == 1 then   -- (scene_on: enter_play ya terminó)
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
    if song_frame == 200 and not speed_f1 then speed_f1 = frame end
    if song_frame == 1200 and not speed_f2 then speed_f2 = frame end
    -- Práctica: la canción debe volver a empezar justo en practice_end, sin fallar, y ahí termina la prueba
    if opt_practice > 0 and not practice_done then
      if not practice_first and state == STATE_PLAY and read8(label("scene_on")) == 1 then
        practice_first = song_frame
      end
      if prev_song_frame and song_frame + 100 < prev_song_frame then
        practice_done = true
        local expect = (read16(label("song_end")) >> 2) * opt_practice
        local alive = true
        for p = 1, num_players do if read8(field(p, "failed")) ~= 0 then alive = false end end
        -- (el último cuadro que se alcanza a ver puede ser el anterior: el reinicio cae a media vuelta del cuadro)
        local ok = alive and (prev_song_frame == expect or prev_song_frame == expect - 1)
                   and read16(label("practice_end")) == expect and scene_drift == 0
        -- Inicio de la práctica (#16): empieza en el cuarto pedido (nunca en o después de donde termina), en una
        -- fila exacta, y desde ahí cada nota del chart suena justo en su cuadro (el motor se adelantó bien)
        local start_text = ""
        do
          local eff = math.min(opt_start, opt_practice - 1)
          local fpr = read8(label("fpr"))
          local start_frame = (((read16(label("song_end")) >> 2) * eff) // fpr) * fpr
          local started = practice_first ~= nil and practice_first >= start_frame and practice_first <= start_frame + 2
          local missed, missed_frames = 0, {}
          for p = 1, num_players do
            for _, n in ipairs(charts[p]) do
              if n.frame >= start_frame + PRACTICE_GRACE + 2 and n.frame < expect - 3 and not triggers[p][n.frame] then
                missed = missed + 1
                if #missed_frames < 8 then missed_frames[#missed_frames + 1] = tostring(n.frame) end
              end
            end
          end
          ok = ok and started and missed == 0
          start_text = string.format(" | inicio en %s (esperado %d), notas sin sonar a tiempo=%d [%s]",
                                     tostring(practice_first), start_frame, missed, table.concat(missed_frames, " "))
        end
        write_file("resultado.txt", string.format("cancion=%d practica: volvio a empezar desde %d (esperado %d), sin fallo=%s, desfase escenario=%d%s -> %s\n",
                   song, prev_song_frame, expect, tostring(alive), scene_drift, start_text, ok and "OK" or "FALLA"))
        emu.stop(ok and 0 or 1)
      end
      prev_song_frame = song_frame
    end
    -- Diagnóstico: cuadros en que el juego se atrasó (la NMI avanzó dos veces en un cuadro de pantalla)
    local nmi = read8(A_NMI_COUNT)
    if prev_nmi and (nmi - prev_nmi) % 256 ~= 1 and #lag_frames < 40 then lag_frames[#lag_frames + 1] = song_frame end
    prev_nmi = nmi
    if num_players == 2 then
      local failed2 = read8(field(2, "failed"))
      if prev_failed2 == 1 and failed2 == 0 then revived = revived + 1 end
      prev_failed2 = failed2
    end
    for p = 1, num_players do
      if read8(field(p, "star_active")) == 1 then star_seen[p] = true end
      -- El contador del "ecualizador" del motor salta a 9 en cada nota nueva
      -- (un contador por canal: 0 = pulso 1, 1 = pulso 2, 2 = triángulo)
      local counter = read8(A_COUNTER + instruments[p])
      local new_note = counter > prev_counter[p]
      if instruments[p] == 3 then
        -- La batería suena por dos canales: el ruido (contador 3) y el DPCM (contador 4). Un golpe nuevo
        -- en cualquiera de los dos cuenta
        local dpcm = read8(A_COUNTER + 4)
        if dpcm > (prev_dpcm[p] or 0) then new_note = true end
        prev_dpcm[p] = dpcm
      end
      if new_note then
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
        if unmuted[p] == 1 then
          write_file("sin_silenciar_J" .. p .. ".txt", string.format("primer cuadro sin silenciar: %d (primera nota %d, volumen %02X)\ncuadros con atraso: %s\nplayer_muted J1=%d J2=%d, sfx=%02X\n",
                     song_frame, chart[1].frame, last_volume[p], table.concat(lag_frames, " "),
                     read8(field(1, "player_muted")), read8(field(2, "player_muted")), read8(A_SFX_PTR_HI)))
        end
      end
      last_volume[p] = nil
    end
    -- El escenario: una captura de cada pose del público (banco 4 quieto, 6 brazos, 8 salto)
    -- y de las luces del poder estelar, la primera vez que aparecen
    local bank, color = read8(A_SCENE_BANK), read8(A_SCENE_COLOR)
    scene_banks[bank] = true
    scene_lights[color] = true
    -- Los saltos del público van con los tiempos de la canción: la fase debe ser (cuadro - primer tiempo) mod cuadros por tiempo
    local song_ptr = read16(A_SONG_PTR)
    local beat = read8(song_ptr + SONG_BEAT_FRAMES)
    -- (Si el cuadro de pantalla termina a media vuelta del juego, song_frame ya avanzó y scene_update
    -- aún no: la fase va un cuadro atrás. Eso solo vale si al cuadro siguiente ya cuadra.)
    -- (en práctica, al llegar a practice_end el juego está reiniciando la canción: enter_play puede quedar a medias)
    -- (y mientras practice_seek adelanta la canción con la pantalla apagada, scene_on aún vale 0)
    if beat > 0 and not (opt_practice > 0 and song_frame >= read16(label("practice_end")))
       and (opt_start == 0 or read8(label("scene_on")) == 1) then
      local expected = (song_frame - read16(song_ptr + SONG_FIRST_BEAT)) % beat
      local phase = read8(A_SCENE_PHASE) % beat   -- (a media vuelta de scene_update vale beat, que es 0 del tiempo siguiente)
      if phase == expected then
        scene_behind = false
      elseif scene_behind or phase ~= (expected - 1) % beat then
        scene_drift = scene_drift + 1
        if scene_drift == 1 then   -- diagnóstico: el primer cuadro en que no cuadró
          write_file("desfase_escenario.txt", string.format("cuadro de la cancion %d: fase %d, esperada %d (cuadros por tiempo %d, atrasada antes=%s)\n",
                     song_frame, phase, expected, beat, tostring(scene_behind)))
        end
      else
        scene_behind = true
      end
    end
    local shot = scene_shots[bank]
    if shot == nil and song_frame > 100 then
      scene_shots[bank] = true
      write_file("captura_escenario_banco" .. bank .. ".png", emu.takeScreenshot())
    end
    if color ~= 0x12 and color ~= 0x22 and color ~= 0x30 and color ~= 0x0F and not scene_shots["c" .. color] then
      scene_shots["c" .. color] = true
      write_file(string.format("captura_escenario_luz%02X.png", color), emu.takeScreenshot())
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
