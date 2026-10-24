// Pruebas del 6502 y del APU de nesplayer.js (las corre test_player.py con Node). Sale con código 1 si algo falla.
const assert = require("assert");
const path = require("path");
const NesPlayer = require(path.join(__dirname, "..", "nesband_tools", "nesplayer.js"));

function machine(program) {
  const bus = new NesPlayer.Bus(new Uint8Array(0x6000), 0xa000);
  bus.rom.set(program, 0x8000);
  return { bus, cpu: new NesPlayer.CPU(bus) };
}
function run(program, setup) {
  const m = machine(program);
  if (setup) setup(m);
  m.cpu.call(0x8000);
  return m;
}
const C = 1, Z = 2, V = 0x40, N = 0x80;
let count = 0;
function test(name, fn) { fn(); count++; }

test("ADC con acarreo y cero", () => {
  const { cpu } = run([0xa9, 0x01, 0x69, 0xff, 0x60]);   // LDA #1; ADC #$FF; RTS
  assert.strictEqual(cpu.a, 0); assert.ok(cpu.p & C); assert.ok(cpu.p & Z);
});
test("ADC desbordamiento con signo", () => {
  const { cpu } = run([0xa9, 0x50, 0x69, 0x50, 0x60]);   // $50 + $50 = $A0
  assert.strictEqual(cpu.a, 0xa0); assert.ok(cpu.p & V); assert.ok(cpu.p & N); assert.ok(!(cpu.p & C));
});
test("SBC", () => {
  const { cpu } = run([0x38, 0xa9, 0x10, 0xe9, 0x01, 0x60]);   // SEC; LDA #$10; SBC #1
  assert.strictEqual(cpu.a, 0x0f); assert.ok(cpu.p & C);
  const under = run([0x38, 0xa9, 0x00, 0xe9, 0x01, 0x60]).cpu;
  assert.strictEqual(under.a, 0xff); assert.ok(!(under.p & C)); assert.ok(under.p & N);
});
test("lazo con DEX y BNE (salto hacia atrás)", () => {
  const { cpu } = run([0xa2, 0x03, 0xca, 0xd0, 0xfd, 0x60]);   // LDX #3; loop: DEX; BNE loop; RTS
  assert.strictEqual(cpu.x, 0); assert.ok(cpu.p & Z);
});
test("JSR y RTS", () => {
  const { cpu } = run([0x20, 0x05, 0x80, 0xea, 0x60, 0xa9, 0x07, 0x60]);   // JSR $8005; NOP; RTS; sub: LDA #7; RTS
  assert.strictEqual(cpu.a, 7);
});
test("(zp),Y y (zp,X)", () => {
  const { bus } = run([0xa9, 0x00, 0x85, 0x10, 0xa9, 0x03, 0x85, 0x11, 0xa0, 0x02, 0xa9, 0x5a, 0x91, 0x10,
    0xa2, 0x04, 0xa9, 0x00, 0x85, 0x14, 0xa9, 0x04, 0x85, 0x15, 0xa9, 0x77, 0x81, 0x10, 0x60]);
  // $10/$11 -> $0300; STA ($10),Y con Y=2 escribe en $0302. $14/$15 -> $0400; STA ($10,X) con X=4 escribe en $0400
  assert.strictEqual(bus.read(0x302), 0x5a);
  assert.strictEqual(bus.ram[0x400 & 0x7ff], 0x77);
});
test("rotaciones y desplazamientos", () => {
  let { cpu } = run([0x38, 0xa9, 0x80, 0x2a, 0x60]);   // SEC; LDA #$80; ROL A -> $01, C=1
  assert.strictEqual(cpu.a, 1); assert.ok(cpu.p & C);
  ({ cpu } = run([0x18, 0xa9, 0x01, 0x6a, 0x60]));      // CLC; LDA #1; ROR A -> 0, C=1, Z
  assert.strictEqual(cpu.a, 0); assert.ok(cpu.p & C); assert.ok(cpu.p & Z);
  ({ cpu } = run([0xa9, 0x81, 0x0a, 0x60]));             // ASL A -> 2, C
  assert.strictEqual(cpu.a, 2); assert.ok(cpu.p & C);
  ({ cpu } = run([0xa9, 0x03, 0x4a, 0x60]));             // LSR A -> 1, C
  assert.strictEqual(cpu.a, 1); assert.ok(cpu.p & C);
});
test("CMP, BIT y la pila", () => {
  let { cpu } = run([0xa9, 0x05, 0xc9, 0x05, 0x60]);
  assert.ok(cpu.p & Z); assert.ok(cpu.p & C);
  ({ cpu } = run([0xa9, 0x01, 0x48, 0xa9, 0x00, 0x68, 0x60]));   // PHA; LDA #0; PLA
  assert.strictEqual(cpu.a, 1);
  const m = run([0xa9, 0xc0, 0x85, 0x20, 0xa9, 0x01, 0x24, 0x20, 0x60]);   // BIT $20: N y V del byte, Z por A & M
  assert.ok(m.cpu.p & N); assert.ok(m.cpu.p & V); assert.ok(m.cpu.p & Z);
});
test("JMP indirecto con el error del cruce de página", () => {
  const { cpu } = run([0x6c, 0xff, 0x02], ({ bus }) => {
    bus.ram[0x2ff] = 0x10; bus.ram[0x200] = 0x80; bus.ram[0x300] = 0x99;   // el byte alto sale de $0200, no de $0300
    bus.rom[0x8010] = 0x60;
  });
  assert.strictEqual(cpu.pc, 0xfff0);
});
test("INC/DEC en memoria y transferencias", () => {
  const { cpu, bus } = run([0xe6, 0x30, 0xe6, 0x30, 0xc6, 0x31, 0xa6, 0x30, 0x8a, 0xa8, 0x60]);
  assert.strictEqual(bus.ram[0x30], 2); assert.strictEqual(bus.ram[0x31], 0xff);
  assert.strictEqual(cpu.y, 2);
});

test("pulso: onda cuadrada con volumen constante y periodo", () => {
  const { bus } = machine([0x60]);
  const apu = bus.apu;
  bus.write(0x4015, 0x01);
  bus.write(0x4000, 0xbf);      // duty 50 %, volumen constante 15
  bus.write(0x4002, 0xfd);      // periodo $0FD
  bus.write(0x4003, 0x08);      // longitud
  let sum = 0, hi = 0, n = 4410;
  for (let i = 0; i < n; i++) { const s = apu.sample(NesPlayer.CPU_HZ / 44100); sum += s; if (s > 0.1) hi++; }
  assert.ok(hi > n * 0.2 && hi < n * 0.8, "ciclo de trabajo cercano a 50 %: " + hi / n);
  assert.ok(sum / n > 0.05);
});
test("canal apagado con $4015 no suena", () => {
  const { bus } = machine([0x60]);
  bus.write(0x4000, 0xbf); bus.write(0x4002, 0xfd); bus.write(0x4003, 0x08);   // sin habilitar el canal
  let peak = 0;
  for (let i = 0; i < 1000; i++) peak = Math.max(peak, bus.apu.sample(NesPlayer.CPU_HZ / 44100));
  assert.strictEqual(peak, 0);
});
test("contador de longitud apaga la nota", () => {
  const { bus } = machine([0x60]);
  bus.write(0x4015, 0x01); bus.write(0x4000, 0x9f); bus.write(0x4002, 0xfd); bus.write(0x4003, 0x18);   // longitud 2: ~ 4 cuartos de cuadro
  let early = 0, late = 0;
  for (let i = 0; i < 44100; i++) { const s = bus.apu.sample(NesPlayer.CPU_HZ / 44100); if (i < 400) early = Math.max(early, s); if (i > 20000) late = Math.max(late, s); }
  assert.ok(early > 0.05); assert.strictEqual(late, 0);
});
test("triángulo y DPCM con el contador delta ($4011)", () => {
  const { bus } = machine([0x60]);
  bus.write(0x4015, 0x04); bus.write(0x4008, 0xff); bus.write(0x400a, 0x40); bus.write(0x400b, 0x08);
  let peak = 0;
  for (let i = 0; i < 4410; i++) peak = Math.max(peak, bus.apu.sample(NesPlayer.CPU_HZ / 44100));
  assert.ok(peak > 0.02);
  bus.write(0x4015, 0x00); bus.write(0x4011, 0x40);
  const s = bus.apu.sample(NesPlayer.CPU_HZ / 44100);
  assert.ok(s > 0.1, "el nivel directo del DPCM suena: " + s);
});

console.log(`${count} pruebas de nesplayer.js bien`);
