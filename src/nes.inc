; =============================================================================
; nes.inc - Direcciones de los registros de hardware del NES
;
; El 6502 no tiene instrucciones especiales para hablar con el video o el
; sonido: cada chip aparece como si fuera memoria en ciertas direcciones.
; Escribir en $2007, por ejemplo, manda un byte a la memoria de video.
; =============================================================================

; --- PPU (chip de video) -----------------------------------------------------
PPUCTRL   = $2000   ; configuración: NMI on/off, nametable base, tablas de tiles
PPUMASK   = $2001   ; qué se dibuja: fondo, sprites, columna izquierda
PPUSTATUS = $2002   ; bit 7 = estamos en vblank. Leerlo reinicia el "latch" de $2005/$2006
OAMADDR   = $2003   ; dirección dentro de la memoria de sprites
PPUSCROLL = $2005   ; scroll: se escribe dos veces (X y luego Y)
PPUADDR   = $2006   ; dirección de VRAM: se escribe dos veces (byte alto y luego bajo)
PPUDATA   = $2007   ; leer/escribir VRAM en la dirección actual (avanza sola)

; --- APU (chip de sonido) ----------------------------------------------------
APU_PULSE1_CTRL  = $4000   ; ciclo de trabajo y volumen/envolvente
APU_PULSE1_SWEEP = $4001
APU_PULSE1_LO    = $4002   ; periodo (tono), byte bajo
APU_PULSE1_HI    = $4003   ; periodo, 3 bits altos + duración
APU_PULSE2_SWEEP = $4005
APU_TRI_CTRL     = $4008
APU_TRI_LO       = $400A
APU_TRI_HI       = $400B
APU_NOISE_CTRL   = $400C
APU_NOISE_PERIOD = $400E
APU_NOISE_LEN    = $400F
APU_DMC_FREQ     = $4010
APU_STATUS       = $4015   ; qué canales están encendidos
APU_FRAME        = $4017   ; contador de cuadros del APU (y la IRQ que generamos apagada)

; --- Otros -------------------------------------------------------------------
OAMDMA = $4014   ; escribir aquí copia 256 bytes de RAM a los sprites de un jalón
JOY1   = $4016   ; control 1
JOY2   = $4017   ; control 2 (solo lectura; escribir aquí es el registro del APU)

; --- Bits del control, en el orden en que quedan después de read_pad ---------
BTN_A      = %10000000
BTN_B      = %01000000
BTN_SELECT = %00100000
BTN_START  = %00010000
BTN_UP     = %00001000
BTN_DOWN   = %00000100
BTN_LEFT   = %00000010
BTN_RIGHT  = %00000001
