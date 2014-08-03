.set MFP_BASE, 0xC0000     | start of IO range for MFP
.set GPDR, MFP_BASE + 0x1  | gpio data reg
.set UDR,  MFP_BASE + 0x2F | uart data register
.set TSR,  MFP_BASE + 0x2D | transmitter status reg
.set RSR,  MFP_BASE + 0x2B | receiver status reg
.set TIL311, 0xC8000       | til311 displays

.data
.align 1
test_str: .asciz "this is a test\n"
_hexmap:  .ascii "0123456789ABCDEF"

.text
.align 2

.global main
.global putc
.global putc_
.global puts
.global puts_

| hex printing functions
.global puthexlong
.global puthexlong_
.global puthexword
.global puthexword_
.global puthexbyte
.global puthexbyte_

main:
	move.b #0xA1, (TIL311)

	move.l #0x15FB, %d0
	bsr puthexword_

	| and we're done here
	rts

| C abi puts
| void puts(const char *s)
puts:
	| move string address into %a2
	move.l 4(%sp), %a0

| ASM abi puts
| - s: %a0
puts_:
	| grab next char, return if equal to '\0'
	move.b (%a0)+, %d0
	beq _puts_end

	| call asm abi putc (expects char in %d0)
	bsr putc_

	| branch back to loop
	bra puts_

_puts_end:
	rts

| C abi putc
| void putc(char c)
putc:
	move.b 7(%sp), %d0

| ASM abi putc
| - c: %d0
putc_:
	| wait for UART to be ready
	btst #7, (TSR)
	beq putc_

	| send char to UART
	move.b %d0, (UDR)
	rts

| C abi puthexlong
| void puthexlong(uint32_t long)
puthexlong:
	move.l 4(%sp), %d0

puthexlong_:
	| save caller's d2
	move.l %d2, -(%sp)
	move.l %d0, %d2

	| high word -> low word
	swap %d0
	bsr puthexword_

	move.w %d2, %d0
	bsr puthexword_

	move.l (%sp)+, %d2
	rts

| C abi puthexword
| void puthexword(uint16_t word)
puthexword:
	move.w 6(%sp), %d0

| ASM abi puthexword
puthexword_:
	| save caller's d2
	move.l %d2, -(%sp)
	move.w %d0, %d2

	| shift high byte down, and print
	lsr.w #8, %d0
	bsr puthexbyte_

	| and print low byte
	move.b %d2, %d0
	bsr puthexbyte_

	| restore to caller
	move.l (%sp)+, %d2
	rts

| C abi puthexbyte
| void puthexbyte(uint8_t byte)
puthexbyte:
	move.b 7(%sp), %d0

| ASM abi puthexbyte
| - num: %d0
puthexbyte_:
	| save caller's d2
	move.l %d2, -(%sp)

	| keep copy of byte in d2
	move.b %d0, %d2
	movea.l #_hexmap, %a3

	| shift and mask high nibble
	lsr.b #4, %d0
	and.b #0xF, %d0
	move.b (%a3, %d0.w), %d0
	bsr putc_

	| and do the same with the low nibble
	move.b %d2, %d0
	and.b #0xF, %d0
	move.b (%a3, %d0.w), %d0
	bsr putc_

	| restore caller's %d2
	move.l (%sp)+, %d2
	rts
