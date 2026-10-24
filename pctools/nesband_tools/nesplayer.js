// Reproductor del editor de charts: un 6502 y el sonido del NES (APU) en JavaScript.
//
// No imita al motor de sonido: ejecuta su código. player.py arma la imagen de 24 KB con el mismo motor de
// FamiStudio y los mismos datos de música que el juego; aquí el CPU llama cada cuadro a famistudio_update,
// el motor escribe en los registros $4000-$4017 y el APU de este archivo los convierte en audio.
//
// Uso:   const audio = NesPlayer.render(player, frames, { sampleRate: 44100 });   // Float32Array
// (en Node: require("./nesplayer.js"), para las pruebas)

const NesPlayer = (function () {
  "use strict";

  const CPU_HZ = 1789773;            // reloj NTSC
  const FRAME_CYCLES = 29780.5;      // un cuadro de video: 60.0988 Hz

  // --- 6502 (instrucciones oficiales) ------------------------------------------------------------------
  const MODES = ["imp", "acc", "imm", "zp", "zpx", "zpy", "abs", "abx", "aby", "ind", "izx", "izy", "rel"];
  const OPCODES = {
    ADC: { imm: 0x69, zp: 0x65, zpx: 0x75, abs: 0x6d, abx: 0x7d, aby: 0x79, izx: 0x61, izy: 0x71 },
    AND: { imm: 0x29, zp: 0x25, zpx: 0x35, abs: 0x2d, abx: 0x3d, aby: 0x39, izx: 0x21, izy: 0x31 },
    ASL: { acc: 0x0a, zp: 0x06, zpx: 0x16, abs: 0x0e, abx: 0x1e },
    BCC: { rel: 0x90 }, BCS: { rel: 0xb0 }, BEQ: { rel: 0xf0 }, BMI: { rel: 0x30 }, BNE: { rel: 0xd0 },
    BPL: { rel: 0x10 }, BVC: { rel: 0x50 }, BVS: { rel: 0x70 },
    BIT: { zp: 0x24, abs: 0x2c },
    BRK: { imp: 0x00 },
    CLC: { imp: 0x18 }, CLD: { imp: 0xd8 }, CLI: { imp: 0x58 }, CLV: { imp: 0xb8 },
    CMP: { imm: 0xc9, zp: 0xc5, zpx: 0xd5, abs: 0xcd, abx: 0xdd, aby: 0xd9, izx: 0xc1, izy: 0xd1 },
    CPX: { imm: 0xe0, zp: 0xe4, abs: 0xec },
    CPY: { imm: 0xc0, zp: 0xc4, abs: 0xcc },
    DEC: { zp: 0xc6, zpx: 0xd6, abs: 0xce, abx: 0xde },
    DEX: { imp: 0xca }, DEY: { imp: 0x88 },
    EOR: { imm: 0x49, zp: 0x45, zpx: 0x55, abs: 0x4d, abx: 0x5d, aby: 0x59, izx: 0x41, izy: 0x51 },
    INC: { zp: 0xe6, zpx: 0xf6, abs: 0xee, abx: 0xfe },
    INX: { imp: 0xe8 }, INY: { imp: 0xc8 },
    JMP: { abs: 0x4c, ind: 0x6c }, JSR: { abs: 0x20 },
    LDA: { imm: 0xa9, zp: 0xa5, zpx: 0xb5, abs: 0xad, abx: 0xbd, aby: 0xb9, izx: 0xa1, izy: 0xb1 },
    LDX: { imm: 0xa2, zp: 0xa6, zpy: 0xb6, abs: 0xae, aby: 0xbe },
    LDY: { imm: 0xa0, zp: 0xa4, zpx: 0xb4, abs: 0xac, abx: 0xbc },
    LSR: { acc: 0x4a, zp: 0x46, zpx: 0x56, abs: 0x4e, abx: 0x5e },
    NOP: { imp: 0xea },
    ORA: { imm: 0x09, zp: 0x05, zpx: 0x15, abs: 0x0d, abx: 0x1d, aby: 0x19, izx: 0x01, izy: 0x11 },
    PHA: { imp: 0x48 }, PHP: { imp: 0x08 }, PLA: { imp: 0x68 }, PLP: { imp: 0x28 },
    ROL: { acc: 0x2a, zp: 0x26, zpx: 0x36, abs: 0x2e, abx: 0x3e },
    ROR: { acc: 0x6a, zp: 0x66, zpx: 0x76, abs: 0x6e, abx: 0x7e },
    RTI: { imp: 0x40 }, RTS: { imp: 0x60 },
    SBC: { imm: 0xe9, zp: 0xe5, zpx: 0xf5, abs: 0xed, abx: 0xfd, aby: 0xf9, izx: 0xe1, izy: 0xf1 },
    SEC: { imp: 0x38 }, SED: { imp: 0xf8 }, SEI: { imp: 0x78 },
    STA: { zp: 0x85, zpx: 0x95, abs: 0x8d, abx: 0x9d, aby: 0x99, izx: 0x81, izy: 0x91 },
    STX: { zp: 0x86, zpy: 0x96, abs: 0x8e },
    STY: { zp: 0x84, zpx: 0x94, abs: 0x8c },
    TAX: { imp: 0xaa }, TAY: { imp: 0xa8 }, TSX: { imp: 0xba }, TXA: { imp: 0x8a }, TXS: { imp: 0x9a }, TYA: { imp: 0x98 },
  };
  const NAMES = Object.keys(OPCODES);
  // Cada opcode: id de la operación y modo de direccionamiento
  const OP_ID = new Int16Array(256).fill(-1);
  const OP_MODE = new Uint8Array(256);
  NAMES.forEach((name, id) => {
    for (const [mode, code] of Object.entries(OPCODES[name])) {
      OP_ID[code] = id;
      OP_MODE[code] = MODES.indexOf(mode);
    }
  });
  const ID = Object.fromEntries(NAMES.map((n, i) => [n, i]));

  const F_C = 1, F_Z = 2, F_I = 4, F_D = 8, F_V = 0x40, F_N = 0x80;

  class CPU {
    constructor(bus) {
      this.bus = bus;
      this.a = 0; this.x = 0; this.y = 0; this.sp = 0xff; this.pc = 0; this.p = F_I | 0x20;
    }
    read(addr) { return this.bus.read(addr & 0xffff); }
    write(addr, value) { this.bus.write(addr & 0xffff, value & 0xff); }
    push(v) { this.write(0x100 | this.sp, v); this.sp = (this.sp - 1) & 0xff; }
    pull() { this.sp = (this.sp + 1) & 0xff; return this.read(0x100 | this.sp); }
    flag(mask, on) { if (on) this.p |= mask; else this.p &= ~mask; }
    nz(v) { this.p = (this.p & ~(F_N | F_Z)) | (v & 0x80) | (v === 0 ? F_Z : 0); return v; }

    // Dirección efectiva de un modo (imm devuelve la del propio operando)
    address(mode) {
      let a, ptr;
      switch (mode) {
        case 2: return this.pc++ & 0xffff;                                              // imm
        case 3: return this.read(this.pc++);                                            // zp
        case 4: return (this.read(this.pc++) + this.x) & 0xff;                          // zpx
        case 5: return (this.read(this.pc++) + this.y) & 0xff;                          // zpy
        case 6: a = this.read(this.pc) | (this.read(this.pc + 1) << 8); this.pc += 2; return a;   // abs
        case 7: a = this.read(this.pc) | (this.read(this.pc + 1) << 8); this.pc += 2; return (a + this.x) & 0xffff;
        case 8: a = this.read(this.pc) | (this.read(this.pc + 1) << 8); this.pc += 2; return (a + this.y) & 0xffff;
        case 10: ptr = (this.read(this.pc++) + this.x) & 0xff;                          // (zp,x)
          return this.read(ptr) | (this.read((ptr + 1) & 0xff) << 8);
        case 11: ptr = this.read(this.pc++);                                            // (zp),y
          return ((this.read(ptr) | (this.read((ptr + 1) & 0xff) << 8)) + this.y) & 0xffff;
        default: throw new Error("modo de direccionamiento " + mode);
      }
    }

    adc(m) {
      const sum = this.a + m + (this.p & F_C);
      this.flag(F_V, (~(this.a ^ m) & (this.a ^ sum) & 0x80) !== 0);
      this.flag(F_C, sum > 0xff);
      this.a = this.nz(sum & 0xff);
    }
    compare(r, m) { const d = r - m; this.flag(F_C, r >= m); this.nz(d & 0xff); }
    branch(cond) {
      const off = this.read(this.pc++);
      if (cond) this.pc = (this.pc + (off < 0x80 ? off : off - 256)) & 0xffff;
    }

    step() {
      const code = this.read(this.pc++);
      const id = OP_ID[code];
      if (id < 0) throw new Error(`opcode $${code.toString(16)} no soportado en $${((this.pc - 1) & 0xffff).toString(16)}`);
      const mode = OP_MODE[code];
      let addr = 0, m;
      if (mode !== 0 && mode !== 1 && mode !== 9 && mode !== 12) addr = this.address(mode);
      switch (id) {
        case ID.LDA: this.a = this.nz(this.read(addr)); break;
        case ID.LDX: this.x = this.nz(this.read(addr)); break;
        case ID.LDY: this.y = this.nz(this.read(addr)); break;
        case ID.STA: this.write(addr, this.a); break;
        case ID.STX: this.write(addr, this.x); break;
        case ID.STY: this.write(addr, this.y); break;
        case ID.ADC: this.adc(this.read(addr)); break;
        case ID.SBC: this.adc(this.read(addr) ^ 0xff); break;
        case ID.AND: this.a = this.nz(this.a & this.read(addr)); break;
        case ID.ORA: this.a = this.nz(this.a | this.read(addr)); break;
        case ID.EOR: this.a = this.nz(this.a ^ this.read(addr)); break;
        case ID.CMP: this.compare(this.a, this.read(addr)); break;
        case ID.CPX: this.compare(this.x, this.read(addr)); break;
        case ID.CPY: this.compare(this.y, this.read(addr)); break;
        case ID.BIT:
          m = this.read(addr);
          this.flag(F_Z, (this.a & m) === 0); this.flag(F_N, (m & 0x80) !== 0); this.flag(F_V, (m & 0x40) !== 0);
          break;
        case ID.INC: this.write(addr, this.nz((this.read(addr) + 1) & 0xff)); break;
        case ID.DEC: this.write(addr, this.nz((this.read(addr) - 1) & 0xff)); break;
        case ID.INX: this.x = this.nz((this.x + 1) & 0xff); break;
        case ID.INY: this.y = this.nz((this.y + 1) & 0xff); break;
        case ID.DEX: this.x = this.nz((this.x - 1) & 0xff); break;
        case ID.DEY: this.y = this.nz((this.y - 1) & 0xff); break;
        case ID.ASL: case ID.LSR: case ID.ROL: case ID.ROR: {
          m = mode === 1 ? this.a : this.read(addr);
          const carry = this.p & F_C;
          let r;
          if (id === ID.ASL) { this.flag(F_C, (m & 0x80) !== 0); r = (m << 1) & 0xff; }
          else if (id === ID.LSR) { this.flag(F_C, (m & 1) !== 0); r = m >> 1; }
          else if (id === ID.ROL) { this.flag(F_C, (m & 0x80) !== 0); r = ((m << 1) | carry) & 0xff; }
          else { this.flag(F_C, (m & 1) !== 0); r = (m >> 1) | (carry << 7); }
          this.nz(r);
          if (mode === 1) this.a = r; else this.write(addr, r);
          break;
        }
        case ID.BCC: this.branch(!(this.p & F_C)); break;
        case ID.BCS: this.branch(this.p & F_C); break;
        case ID.BEQ: this.branch(this.p & F_Z); break;
        case ID.BNE: this.branch(!(this.p & F_Z)); break;
        case ID.BMI: this.branch(this.p & F_N); break;
        case ID.BPL: this.branch(!(this.p & F_N)); break;
        case ID.BVS: this.branch(this.p & F_V); break;
        case ID.BVC: this.branch(!(this.p & F_V)); break;
        case ID.JMP:
          if (mode === 9) {   // indirecto, con el famoso error del cruce de página
            const p = this.read(this.pc) | (this.read(this.pc + 1) << 8);
            this.pc = this.read(p) | (this.read((p & 0xff00) | ((p + 1) & 0xff)) << 8);
          } else this.pc = addr;
          break;
        case ID.JSR: {
          const ret = (this.pc - 1) & 0xffff;
          this.push(ret >> 8); this.push(ret & 0xff);
          this.pc = addr;
          break;
        }
        case ID.RTS: { const lo = this.pull(); this.pc = ((this.pull() << 8 | lo) + 1) & 0xffff; break; }
        case ID.RTI: { this.p = (this.pull() & ~0x10) | 0x20; const lo = this.pull(); this.pc = this.pull() << 8 | lo; break; }
        case ID.BRK: {
          const ret = (this.pc + 1) & 0xffff;
          this.push(ret >> 8); this.push(ret & 0xff); this.push(this.p | 0x30);
          this.p |= F_I;
          this.pc = this.read(0xfffe) | (this.read(0xffff) << 8);
          break;
        }
        case ID.PHA: this.push(this.a); break;
        case ID.PHP: this.push(this.p | 0x30); break;
        case ID.PLA: this.a = this.nz(this.pull()); break;
        case ID.PLP: this.p = (this.pull() & ~0x10) | 0x20; break;
        case ID.TAX: this.x = this.nz(this.a); break;
        case ID.TAY: this.y = this.nz(this.a); break;
        case ID.TXA: this.a = this.nz(this.x); break;
        case ID.TYA: this.a = this.nz(this.y); break;
        case ID.TSX: this.x = this.nz(this.sp); break;
        case ID.TXS: this.sp = this.x; break;
        case ID.CLC: this.flag(F_C, false); break;
        case ID.SEC: this.flag(F_C, true); break;
        case ID.CLD: this.flag(F_D, false); break;
        case ID.SED: this.flag(F_D, true); break;
        case ID.CLI: this.flag(F_I, false); break;
        case ID.SEI: this.flag(F_I, true); break;
        case ID.CLV: this.flag(F_V, false); break;
        case ID.NOP: break;
        default: throw new Error("operación sin implementar: " + NAMES[id]);
      }
    }

    // Ejecuta la rutina en `addr` (como un JSR) hasta que vuelve. Devuelve cuántas instrucciones corrió.
    call(addr, a, x, y, limit = 2000000) {
      const RET = 0xfff0;   // dirección que nunca se ejecuta: al volver, el RTS cae aquí
      if (a !== undefined) this.a = a;
      if (x !== undefined) this.x = x;
      if (y !== undefined) this.y = y;
      this.push((RET - 1) >> 8); this.push((RET - 1) & 0xff);
      this.pc = addr;
      let steps = 0;
      while (this.pc !== RET) {
        this.step();
        if (++steps > limit) throw new Error(`la rutina de $${addr.toString(16)} no termina`);
      }
      return steps;
    }
  }

  // --- APU ---------------------------------------------------------------------------------------------
  const LENGTHS = [10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14,
    12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30];
  const DUTIES = [[0, 1, 0, 0, 0, 0, 0, 0], [0, 1, 1, 0, 0, 0, 0, 0], [0, 1, 1, 1, 1, 0, 0, 0], [1, 0, 0, 1, 1, 1, 1, 1]];
  const NOISE_PERIODS = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068];
  const DMC_PERIODS = [428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54];

  // Cada canal avanza `cycles` ciclos de CPU y devuelve la integral de su salida (nivel x ciclos): así el
  // promedio de cada muestra de audio es exacto aunque el tono sea más agudo que la tasa de muestreo.

  class Envelope {
    constructor() { this.start = false; this.loop = false; this.constant = false; this.volume = 0; this.divider = 0; this.decay = 0; }
    clock() {
      if (this.start) { this.start = false; this.decay = 15; this.divider = this.volume; }
      else if (this.divider === 0) {
        this.divider = this.volume;
        if (this.decay > 0) this.decay--; else if (this.loop) this.decay = 15;
      } else this.divider--;
    }
    output() { return this.constant ? this.volume : this.decay; }
  }

  class Pulse {
    constructor(isFirst) {
      this.isFirst = isFirst; this.enabled = false; this.length = 0; this.env = new Envelope();
      this.duty = 0; this.seq = 0; this.period = 0; this.timer = 0;
      this.sweepEnable = false; this.sweepPeriod = 0; this.sweepNegate = false; this.sweepShift = 0;
      this.sweepDiv = 0; this.sweepReload = false;
    }
    target() {
      const change = this.period >> this.sweepShift;
      return this.sweepNegate ? this.period - change - (this.isFirst ? 1 : 0) : this.period + change;
    }
    muted() { return this.period < 8 || this.target() > 0x7ff; }
    level() {
      if (!this.enabled || this.length === 0 || this.muted() || !DUTIES[this.duty][this.seq]) return 0;
      return this.env.output();
    }
    clockSweep() {
      if (this.sweepDiv === 0 && this.sweepEnable && this.sweepShift > 0 && !this.muted()) this.period = this.target();
      if (this.sweepDiv === 0 || this.sweepReload) { this.sweepDiv = this.sweepPeriod; this.sweepReload = false; }
      else this.sweepDiv--;
    }
    clockLength() { if (!this.env.loop && this.length > 0) this.length--; }
    write(reg, v) {
      switch (reg) {
        case 0: this.duty = v >> 6; this.env.loop = (v & 0x20) !== 0; this.env.constant = (v & 0x10) !== 0; this.env.volume = v & 15; break;
        case 1: this.sweepEnable = (v & 0x80) !== 0; this.sweepPeriod = (v >> 4) & 7; this.sweepNegate = (v & 8) !== 0;
          this.sweepShift = v & 7; this.sweepReload = true; break;
        case 2: this.period = (this.period & 0x700) | v; break;
        case 3: this.period = (this.period & 0xff) | ((v & 7) << 8); if (this.enabled) this.length = LENGTHS[v >> 3];
          this.seq = 0; this.env.start = true; break;
      }
    }
    run(cycles) {
      let acc = 0;
      while (cycles > 0) {
        if (this.timer <= 0) this.timer = (this.period + 1) * 2;
        const step = Math.min(cycles, this.timer);
        acc += this.level() * step;
        this.timer -= step; cycles -= step;
        if (this.timer <= 0) this.seq = (this.seq + 1) & 7;
      }
      return acc;
    }
  }

  class Triangle {
    constructor() {
      this.enabled = false; this.length = 0; this.control = false; this.linearValue = 0; this.linear = 0;
      this.reload = false; this.period = 0; this.timer = 0; this.seq = 0; this.out = 0;
    }
    write(reg, v) {
      switch (reg) {
        case 0: this.control = (v & 0x80) !== 0; this.linearValue = v & 0x7f; break;
        case 2: this.period = (this.period & 0x700) | v; break;
        case 3: this.period = (this.period & 0xff) | ((v & 7) << 8); if (this.enabled) this.length = LENGTHS[v >> 3];
          this.reload = true; break;
      }
    }
    clockLinear() {
      if (this.reload) this.linear = this.linearValue; else if (this.linear > 0) this.linear--;
      if (!this.control) this.reload = false;
    }
    clockLength() { if (!this.control && this.length > 0) this.length--; }
    run(cycles) {
      let acc = 0;
      while (cycles > 0) {
        if (this.timer <= 0) this.timer = this.period + 1;
        const step = Math.min(cycles, this.timer);
        acc += this.out * step;
        this.timer -= step; cycles -= step;
        if (this.timer <= 0 && this.length > 0 && this.linear > 0) {
          this.seq = (this.seq + 1) & 31;
          this.out = this.seq < 16 ? 15 - this.seq : this.seq - 16;
        }
      }
      return acc;
    }
  }

  class Noise {
    constructor() { this.enabled = false; this.length = 0; this.env = new Envelope(); this.mode = false; this.period = NOISE_PERIODS[0]; this.timer = 0; this.shift = 1; }
    level() { return (!this.enabled || this.length === 0 || (this.shift & 1)) ? 0 : this.env.output(); }
    clockLength() { if (!this.env.loop && this.length > 0) this.length--; }
    write(reg, v) {
      switch (reg) {
        case 0: this.env.loop = (v & 0x20) !== 0; this.env.constant = (v & 0x10) !== 0; this.env.volume = v & 15; break;
        case 2: this.mode = (v & 0x80) !== 0; this.period = NOISE_PERIODS[v & 15]; break;
        case 3: if (this.enabled) this.length = LENGTHS[v >> 3]; this.env.start = true; break;
      }
    }
    run(cycles) {
      let acc = 0;
      while (cycles > 0) {
        if (this.timer <= 0) this.timer = this.period;
        const step = Math.min(cycles, this.timer);
        acc += this.level() * step;
        this.timer -= step; cycles -= step;
        if (this.timer <= 0) {
          const fb = (this.shift & 1) ^ ((this.shift >> (this.mode ? 6 : 1)) & 1);
          this.shift = (this.shift >> 1) | (fb << 14);
        }
      }
      return acc;
    }
  }

  class DMC {
    constructor(bus) {
      this.bus = bus; this.enabled = false; this.irq = false; this.loop = false; this.period = DMC_PERIODS[0];
      this.timer = 0; this.out = 0; this.sampleAddr = 0xc000; this.sampleLen = 1;
      this.addr = 0xc000; this.remaining = 0; this.buffer = -1; this.shift = 0; this.bits = 8; this.silence = true;
    }
    write(reg, v) {
      switch (reg) {
        case 0: this.irq = (v & 0x80) !== 0; this.loop = (v & 0x40) !== 0; this.period = DMC_PERIODS[v & 15]; break;
        case 1: this.out = v & 0x7f; break;
        case 2: this.sampleAddr = 0xc000 + v * 64; break;
        case 3: this.sampleLen = v * 16 + 1; break;
      }
    }
    restart() { this.addr = this.sampleAddr; this.remaining = this.sampleLen; this.fill(); }
    fill() {
      if (this.buffer >= 0 || this.remaining === 0) return;
      this.buffer = this.bus.read(this.addr);
      this.addr = ((this.addr + 1) & 0xffff) | 0x8000;
      if (--this.remaining === 0 && this.loop) { this.addr = this.sampleAddr; this.remaining = this.sampleLen; }
    }
    run(cycles) {
      let acc = 0;
      while (cycles > 0) {
        if (this.timer <= 0) this.timer = this.period;
        const step = Math.min(cycles, this.timer);
        acc += this.out * step;
        this.timer -= step; cycles -= step;
        if (this.timer <= 0) {
          if (!this.silence) {
            if (this.shift & 1) { if (this.out <= 125) this.out += 2; } else if (this.out >= 2) this.out -= 2;
            this.shift >>= 1;
          }
          if (--this.bits === 0) {
            this.bits = 8;
            if (this.buffer < 0) this.silence = true;
            else { this.silence = false; this.shift = this.buffer; this.buffer = -1; this.fill(); }
          }
        }
      }
      return acc;
    }
  }

  class APU {
    constructor(bus, log) {
      this.p1 = new Pulse(true); this.p2 = new Pulse(false); this.tri = new Triangle(); this.noise = new Noise();
      this.dmc = new DMC(bus);
      this.cycle = 0; this.fiveStep = false; this.step = 0; this.frameStart = 0; this.nextEvent = 7457;
      this.log = log || null; this.frame = 0;
      this.hp = 0; this.prev = 0;
    }
    write(addr, v) {
      if (this.log) this.log.push([this.frame, addr, v]);
      if (addr < 0x4004) this.p1.write(addr & 3, v);
      else if (addr < 0x4008) this.p2.write(addr & 3, v);
      else if (addr < 0x400c) this.tri.write(addr & 3, v);
      else if (addr < 0x4010) this.noise.write(addr & 3, v);
      else if (addr < 0x4014) this.dmc.write(addr & 3, v);
      else if (addr === 0x4015) {
        this.p1.enabled = (v & 1) !== 0; if (!this.p1.enabled) this.p1.length = 0;
        this.p2.enabled = (v & 2) !== 0; if (!this.p2.enabled) this.p2.length = 0;
        this.tri.enabled = (v & 4) !== 0; if (!this.tri.enabled) this.tri.length = 0;
        this.noise.enabled = (v & 8) !== 0; if (!this.noise.enabled) this.noise.length = 0;
        this.dmc.enabled = (v & 16) !== 0;
        if (!this.dmc.enabled) this.dmc.remaining = 0; else if (this.dmc.remaining === 0) this.dmc.restart();
      } else if (addr === 0x4017) {
        this.fiveStep = (v & 0x80) !== 0; this.step = 0; this.frameStart = this.cycle; this.nextEvent = this.cycle + 7457;
        if (this.fiveStep) { this.quarter(); this.half(); }
      }
    }
    read(addr) {
      if (addr !== 0x4015) return 0;
      return (this.p1.length > 0 ? 1 : 0) | (this.p2.length > 0 ? 2 : 0) | (this.tri.length > 0 ? 4 : 0) |
        (this.noise.length > 0 ? 8 : 0) | (this.dmc.remaining > 0 ? 16 : 0);
    }
    quarter() { this.p1.env.clock(); this.p2.env.clock(); this.noise.env.clock(); this.tri.clockLinear(); }
    half() {
      for (const c of [this.p1, this.p2, this.tri, this.noise]) c.clockLength();
      this.p1.clockSweep(); this.p2.clockSweep();
    }
    // Eventos del contador de cuadros (4 o 5 pasos), en ciclos de CPU
    frameEvent() {
      const steps = this.fiveStep ? [7457, 14913, 22371, 29829, 37281] : [7457, 14913, 22371, 29829];
      const kinds = this.fiveStep ? [1, 3, 1, 0, 3] : [1, 3, 1, 3];   // 1 = cuarto de cuadro, 3 = cuarto y mitad
      const kind = kinds[this.step];
      if (kind) { this.quarter(); if (kind === 3) this.half(); }
      if (++this.step === steps.length) { this.step = 0; this.frameStart += this.fiveStep ? 37282 : 29830; }
      this.nextEvent = this.frameStart + steps[this.step];
    }
    // Una muestra de audio que dura `cycles` ciclos de CPU
    sample(cycles) {
      let remaining = cycles, a1 = 0, a2 = 0, at = 0, an = 0, ad = 0;
      while (remaining > 1e-9) {
        const step = Math.min(remaining, this.nextEvent - this.cycle);
        if (step > 0) {
          a1 += this.p1.run(step); a2 += this.p2.run(step); at += this.tri.run(step);
          an += this.noise.run(step); ad += this.dmc.run(step);
          this.cycle += step; remaining -= step;
        }
        if (this.cycle >= this.nextEvent - 1e-9) this.frameEvent();
      }
      const p = (a1 + a2) / cycles, t = at / cycles, n = an / cycles, d = ad / cycles;
      const pulse = p > 0 ? 95.88 / (8128 / p + 100) : 0;
      const tnd = t + n + d > 0 ? 159.79 / (1 / (t / 8227 + n / 12241 + d / 22638) + 100) : 0;
      return pulse + tnd;
    }
  }

  // --- Memoria del NES con la imagen del reproductor --------------------------------------------------------
  class Bus {
    constructor(image, start, log) {
      this.ram = new Uint8Array(0x800);
      this.rom = new Uint8Array(0x10000);
      this.rom.set(image, start);
      this.apu = new APU(this, log);
    }
    read(addr) {
      if (addr < 0x2000) return this.ram[addr & 0x7ff];
      if (addr >= 0x4000 && addr < 0x4018) return this.apu.read(addr);
      if (addr >= 0x8000) return this.rom[addr];
      return 0;
    }
    write(addr, v) {
      if (addr < 0x2000) this.ram[addr & 0x7ff] = v;
      else if (addr >= 0x4000 && addr < 0x4018) this.apu.write(addr, v);
    }
  }

  function decodeBase64(text) {
    if (typeof Buffer !== "undefined") return new Uint8Array(Buffer.from(text, "base64"));
    const bin = atob(text), out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  // La canción como la toca el juego: famistudio_init con los datos de música y, cuadro a cuadro,
  // famistudio_update. `player` es lo que devuelve /api/player. Devuelve un objeto con el audio.
  class Song {
    constructor(player, options = {}) {
      this.sampleRate = options.sampleRate || 44100;
      this.bus = new Bus(decodeBase64(player.image), player.start, options.log);
      this.cpu = new CPU(this.bus);
      this.routines = player.routines;
      const rom = this.bus.rom;
      this.cpu.call(this.routines.famistudio_init, 1, rom[player.start], rom[player.start + 1]);   // NTSC, datos de música
      this.cpu.call(this.routines.famistudio_music_play, 0);
      this.cyclesPerSample = CPU_HZ / this.sampleRate;
      this.owed = 0;   // ciclos de CPU de cuadros anteriores que aún no se vuelven muestras
    }
    // Avanza un cuadro de video: corre el motor y devuelve las muestras de ese cuadro
    frame(index) {
      this.bus.apu.frame = index;
      this.cpu.call(this.routines.famistudio_update);
      this.owed += FRAME_CYCLES;
      const count = Math.floor(this.owed / this.cyclesPerSample);
      this.owed -= count * this.cyclesPerSample;
      const out = new Float32Array(count);
      const apu = this.bus.apu;
      for (let i = 0; i < count; i++) {
        const s = apu.sample(this.cyclesPerSample);
        // Filtro pasa-altas (~37 Hz) como el del NES: quita el nivel de continua
        apu.hp = apu.hp * 0.9948 + s - apu.prev; apu.prev = s;
        out[i] = apu.hp * 1.6;
      }
      return out;
    }
  }

  // Toca `frames` cuadros y devuelve todo el audio (Float32Array mono). `onProgress(fracción)` se llama
  // de vez en cuando; si `yieldFn` existe (una función async) se espera con él para no congelar la página.
  async function render(player, frames, options = {}) {
    const song = new Song(player, options);
    const chunks = [];
    let total = 0;
    for (let f = 0; f < frames; f++) {
      const part = song.frame(f);
      chunks.push(part); total += part.length;
      if (f % 120 === 119) {
        if (options.onProgress) options.onProgress(f / frames);
        if (options.yieldFn) await options.yieldFn();
      }
    }
    const audio = new Float32Array(total);
    let at = 0;
    for (const c of chunks) { audio.set(c, at); at += c.length; }
    return { audio, sampleRate: song.sampleRate, log: options.log || null };
  }

  return { CPU, APU, Bus, Song, render, FRAME_CYCLES, CPU_HZ };
})();

if (typeof module !== "undefined") module.exports = NesPlayer;
