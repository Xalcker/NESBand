-- =============================================================================
-- mame_shim.lua - La API de Lua de Mesen 2 que usa tests/autoplay.lua, sobre MAME
--
-- Permite correr el mismo autoplay.lua en MAME (`uv run nesband test --emulador mame`), sin cambiarlo. Solo
-- implementa lo que el bot usa: emu.read, emu.getLabelAddress, emu.addMemoryCallback (escrituras),
-- emu.addEventCallback (endFrame, inputPolled), emu.setInput, emu.getState (cpu.a, cpu.cycleCount),
-- emu.takeScreenshot y emu.stop.
--
-- Variables de entorno:
--   SHIM_DBG      el .dbg de cc65 junto a la ROM (de ahí salen las direcciones de los símbolos)
--   SHIM_SCRIPT   el script del bot (tests/autoplay.lua)
--   TEST_OUT      carpeta de salida; emu.stop(código) deja el código en TEST_OUT/exitcode.txt
--
-- Detalles que importan:
--  * MAME desuscribe lo que recoge el recolector de basura: todo lo que devuelven add_machine_frame_notifier y
--    install_*_tap se guarda en KEEP/SUB. Sin eso, el bot deja de ejecutarse a los ~2 s sin avisar.
--  * MAME aplica los botones del ioport con un cuadro de retraso, y el bot necesita que el juego los vea en el
--    cuadro en que los lee (como Mesen). Por eso se imita el registro de desplazamiento del control: el bot deja
--    los botones en `cur`, al bajar el strobe de $4016 se congelan y cada lectura de $4016/$4017 devuelve el
--    siguiente bit. Con el ioport, cada nota sostenida se juzgaba un cuadro tarde y perdía su primer +10.
--  * cpu.cycleCount sale del reloj de MAME por el reloj NTSC fijo (la API de Lua no da el de la CPU): sirve para
--    medir la carga por cuadro, no para contar ciclos exactos.
-- =============================================================================
local machine = manager.machine
local cpu = machine.devices[":maincpu"]
local mem = cpu.spaces["program"]
local outdir = os.getenv("TEST_OUT") or "."
local KEEP = {}

-- símbolos del .dbg
local labels = {}
for line in io.lines((assert(os.getenv("SHIM_DBG"), "falta SHIM_DBG"))) do
  local name, val = line:match('^sym.-name="([^"]+)".-val=0x(%x+)')
  if name and line:find("type=lab", 1, true) then labels[name] = tonumber(val, 16) end
end

emu.memType = { nesMemory = 1 }
emu.eventType = { endFrame = 1, inputPolled = 2 }
emu.callbackType = { write = 1 }

function emu.getLabelAddress(name)
  if labels[name] then return { address = labels[name] } end
  return nil
end
function emu.read(addr, _, _) return mem:read_u8(addr) end

function emu.addMemoryCallback(cb, _, first, last)
  KEEP[#KEEP + 1] = mem:install_write_tap(first, last or first, "shim" .. #KEEP,
    function(offset, data, mask) cb(offset, data) end)
end

local end_frame, polled = {}, {}
function emu.addEventCallback(cb, kind)
  if kind == emu.eventType.endFrame then end_frame[#end_frame + 1] = cb else polled[#polled + 1] = cb end
end

-- Controles: registro de desplazamiento del NES (orden de lectura: A, B, Select, Start, Arriba, Abajo, Izq., Der.)
local ORDER = { "a", "b", "select", "start", "up", "down", "left", "right" }
local cur = { [0] = {}, [1] = {} }
function emu.setInput(buttons, _, controller) cur[controller] = buttons end

local strobe, latch, idx = 0, { [0] = 0, [1] = 0 }, { [0] = 0, [1] = 0 }
local polled_this_frame = false
KEEP[#KEEP + 1] = mem:install_write_tap(0x4016, 0x4016, "shim_strobe", function(offset, data, mask)
  local s = data & 1
  -- El juego lee el control varias veces por cuadro (4 en NESBand). Mesen avisa "inputPolled" una vez por cuadro y
  -- el juego ve los mismos botones en todas sus lecturas; si el bot se llamara en cada una, una pulsación de un solo
  -- cuadro (las marcas de la pausa) llegaría solo a la primera lectura y el juego, que se queda con la última, no la vería.
  if s == 1 and strobe == 0 and not polled_this_frame then
    polled_this_frame = true
    for _, cb in ipairs(polled) do cb() end
  end
  if s == 0 and strobe == 1 then                       -- el control guarda su estado
    for c = 0, 1 do
      local v = 0
      for i, key in ipairs(ORDER) do if cur[c][key] then v = v | (1 << (i - 1)) end end
      latch[c], idx[c] = v, 0
    end
  end
  strobe = s
end)
for c = 0, 1 do
  KEEP[#KEEP + 1] = mem:install_read_tap(0x4016 + c, 0x4016 + c, "shim_read" .. c, function(offset, data, mask)
    local bit
    if strobe == 1 then
      bit = cur[c]["a"] and 1 or 0
    elseif idx[c] < 8 then
      bit = (latch[c] >> idx[c]) & 1
      idx[c] = idx[c] + 1
    else
      bit = 1
    end
    return (data & 0xFE) | bit
  end)
end

function emu.getState()
  return { ["cpu.a"] = cpu.state["A"].value, ["cpu.cycleCount"] = math.floor(machine.time:as_double() * 1789772.5) }
end

function emu.takeScreenshot()
  local name = "shim_tmp.png"
  machine.screens[":screen"]:snapshot(name)            -- MAME lo guarda en su carpeta de capturas (la de TEST_OUT)
  local path = outdir .. "/" .. name
  local f = io.open(path, "rb")
  if not f then return "" end
  local d = f:read("a")
  f:close()
  os.remove(path)
  return d
end

function emu.stop(code)
  local f = io.open(outdir .. "/exitcode.txt", "w")
  f:write(tostring(code or 0))
  f:close()
  machine:exit()
end

SUB = emu.add_machine_frame_notifier(function()
  polled_this_frame = false
  for _, cb in ipairs(end_frame) do cb() end
end)

dofile((assert(os.getenv("SHIM_SCRIPT"), "falta SHIM_SCRIPT")))
