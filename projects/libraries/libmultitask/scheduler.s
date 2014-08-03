| scheduler.s: multitasking scheduler for the 68k
| Free space can be found from 0x400 to 0x1000
| (from end of vector table up to the bootloader)

| I/O addresses
.set IO_BASE, 0xC0000
.set MFP_BASE, IO_BASE
.set MFP_IERB, MFP_BASE + 0x09 | interrupt enable register, b
.set MFP_IMRB, MFP_BASE + 0x15 | interrupt mask register, b
.set MFP_TDDR, MFP_BASE + 0x25 | timer d data register
.set MFP_TCDCR, MFP_BASE +0x1D | timer c & d control register
.set MFP_VR,   MFP_BASE + 0x17 | vector register (high nibble of vector number)

.set TIL311, IO_BASE + 0x8000

.extern putc
.extern main

| scheduler timer (longword)
.global mt_time
.set mt_time, 0x400

| pointer to currently scheduled task (longword)
.global current_task
.set current_task, 0x404

| address of the `trap 0' vector in the vector table
.set trap0_vect, 0x80
.set millis_vect, 0x210

| main method to execute when initialized
.extern main

| entrypoint for the scheduler, initialize state and execute `main' in
| usermode
.global _kernel_start
_kernel_start:

  | initialize scheduler state
  move.l #0, (mt_time)
  move.l #0, (current_task)

  | set up MFP interrupt configuration
  move.b #0x4, (MFP_VR) | start MFP vectors at 0x40 and up

  | install handler for timer D vector
  | timer D's low nibble is 0x4, so (MFP_VR << 4) | (timer d) = 0x44
  | so install handler at (0x44 * 4)
  movea.l #0x44, %a0
  adda.l %a0, %a0 | mul by 4
  adda.l %a0, %a0
  move.l #on_timer_d, (%a0)

  | initialize timer D to drive millis_vect
  | 3.6864mhz, 200 prescaler, 184 data is ~ a 100hz interrupt
  move.b #184,  (MFP_TDDR)
  ori.b  #0x07, (MFP_TCDCR)
  ori.b  #0x10, (MFP_IMRB)
  ori.b  #0x10, (MFP_IERB)

  | for now, just jump straight to main
  jsr main

| handler for timer D interrupt
on_timer_d:
  | for now, just send 'T' over serial
  move.b #'T', -(%sp)
  jsr putc
  addq.l #4, %sp

  rte

| handler for trap0; e.g.
on_trap0:
  rte
