.set MFP_BASE, 0xC0000     | start of IO range for MFP
.set GPDR, MFP_BASE + 0x01 | gpio data reg
.set MFP_DDR,  MFP_BASE + 0x05 | gpio data direction
.set UDR,  MFP_BASE + 0x2F | uart data register
.set TSR,  MFP_BASE + 0x2D | transmitter status reg
.set RSR,  MFP_BASE + 0x2B | receiver status reg


.set TIL311, 0xC8000       | til311 displays

.extern putc

.data
.align 1
test_str: .asciz "this is a test\n"
_hexmap:  .ascii "0123456789ABCDEF"

.text
.align 2

| linker bug requires mt_init_ is declared here
| .global mt_init_

.global main
main:
	move.b #0xA1, (TIL311)

	move.l #test_str, -(%sp)
	jsr printf
	addq.l #4, %sp

	| and we're done here
	rts
