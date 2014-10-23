.align 4
.text

.global _start
.global _exit

.extern __stack_start
.extern __bss_start
.extern __start_func

.extern __data_longs
.extern __bss_longs

.extern __data_start_romloc
.extern __data_start_ramloc

.set IO_BASE, 0xC0000
.set TIL311, IO_BASE + 0x8000

| bootable magic
.long 0xc141c340

| indicate that this area of ROM is bootable
_start:
  move.b #0xC1, (TIL311)

  move.l #__stack_start, %a7

  move.b #0xC2, (TIL311)

  | load .data into ram
  move.l #__data_longs, %d0
  tst.l %d0
  beq endinit_data
  trap #10

  movea.l #__data_start_romloc, %a0
  movea.l #__data_start_ramloc, %a1
init_data:
  move.l (%a0)+, (%a1)+
  dbra %d0, init_data

endinit_data:
  move.b #0xC3, (TIL311)

  | clear the bss section
  move.l #__bss_longs, %d0
  tst.l %d0
  beq endinit_bss

  movea.l #__bss_start, %a0
init_bss:
  clr.l (%a0)+
  dbra %d0, init_bss
endinit_bss:

  move.b #0xC4, (TIL311)

  jsr __start_func

  | done? infinite loop.
_exit:
  bra _exit
