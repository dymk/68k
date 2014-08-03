| Test bootloader for the 68k
.global rom_boot_

.set IO_BASE, 0xC0000
.set MFP,     IO_BASE
.set TIL311,  IO_BASE + 0x08000

| beginning and ending address of the bootloader
.extern bl_begin
.extern bl_size
.extern bl_reloc_address
.extern bl_stack_pointer
.extern loader_start

.macro TIL_DEBUG byte
  move.b #\byte, (TIL311)
.endm

| Initial stack and program counter burned into RAM
| SP is highest RAM (grows downward)
| PC is where rom_boot_ begins
| Comment out when testing in RAM
| .data
| _isp: .long stack_pointer
| _ipc: .long 0x80008

.text
.align 2
rom_boot_:
  | okay, lets boot
  TIL_DEBUG 0x01

  | reset any connected peripherials
  reset

  | reset stack in case rom_boot_ was jumped to
  move.l #bl_stack_pointer, %sp

  | load source address to begin copying from
  lea (bl_begin, %pc), %a0

  | and destination address to copy to
  movea.l #bl_reloc_address, %a1

  | load number of words to copy
  move.l #bl_size, %d0

_loop:
  move.l (%a0)+, (%a1)+
  dbra %d0, _loop

  | absolute jump to loader_start
  jmp loader_start
