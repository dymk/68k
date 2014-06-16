/*
  Programmer for 39SF040 flash
*/

/*
addressing shift registers pins -> pins on flash
SR clock: PIN2, PORTD << 2 (orange) (red probe, ch 0)
SR latch: PIN3, PORTD << 3 (blue)   (brown probe, ch 1)
SR data:  PIN4, PORTD << 4 (yellow) (yellow probe, ch 2)

first SR:
5 => 18
6 => 17
7 => 16

second SR:
0 => 15
1 => 14
2 => 13
3 => 12
4 => 11
5 => 10
6 => 9
7 => 8

third SR:
0 => 7
1 => 6
2 => 5
3 => 4
4 => 3
5 => 2
6 => 1
7 => 0

Mappings for the Flash:
#CE => PINC.2, pin A0 (red jumper)
#OE => PINC.3, pin A1 (blue jumper)
#WE => PINC.4, pin A2 (yellow jumper)
*/
// chip enable
#define CE A0
// read
#define OE A1
// write
#define WE A2

#include "lib.h"

#define SR_CLK 2
#define SR_LATCH 3
#define SR_DATA 4

#define DEBUG 1

// the setup routine runs once when you press reset:
void setup() {
	Serial.begin(9600);

	// initialize the digital pin as an output.
	pinMode(SR_CLK, OUTPUT);
	pinMode(SR_LATCH, OUTPUT);
	pinMode(SR_DATA, OUTPUT);

	pinMode(CE, OUTPUT);
	pinMode(OE, OUTPUT);
	pinMode(WE, OUTPUT);

	// disable flash chip
	digitalWrite(CE, HIGH);
	digitalWrite(OE, HIGH);
	digitalWrite(WE, HIGH);

	// sanity checks
	if(sizeof(uint16_t) != 2)
		Serial.println("uint16_t is not 2 bytes");
}

// Sets the address bus
void set_addr(uint32_t addr) {
#if DEBUG
	Serial.print("Setting address to: 0x");
	Serial.println(addr, HEX);
#endif

	// bring latch low
	digitalWrite(SR_LATCH, LOW);

	// 24 bits of addr, as three SRs are used
	for(unsigned int i = 0; i < 24; i++) {

		// write the bit
		digitalWrite(SR_DATA, (addr >> i) & 1);

		// toggle clock
		digitalWrite(SR_CLK, LOW);
		digitalWrite(SR_CLK, HIGH);
	}

	// and toggle latch to write it to the output
	digitalWrite(SR_CLK, LOW);
	digitalWrite(SR_LATCH, HIGH);
	digitalWrite(SR_LATCH, LOW);

	Serial.println("");
}

// Sets 'data' to the databus
void set_data(uint8_t data) {
	// lower 6 bits is PORTB0-5,
	// upper nibble is PORTC0-3

#if DEBUG
	Serial.print("Writing to data: 0x");
	Serial.println(data, HEX);
#endif

	DDRB |= 0x3F; // 0b111111
	DDRC |= 0x3;  // 0b11

	PORTB = data & 0x3F;
	PORTC = (data >> 6) & 0x3;
}

// Reads a byte from the databus
uint8_t read_data() {
	DDRB &= ~0x3F;
	DDRC &= ~0x3;

	uint8_t ret;
	ret = ((PINC & 0x3) << 6) | (PINB & 0x3F);

	return ret;
}

// Read the data at address 'addr'
uint8_t read_from_addr(uint32_t addr) {
	set_addr(addr);
	asm("nop\n nop\n");

	digitalWrite(CE, LOW);
	digitalWrite(OE, LOW);
	asm("nop\n nop\n");

	uint8_t ret = read_data();
	digitalWrite(CE, HIGH);
	digitalWrite(OE, HIGH);

	return ret;
}

// Latches the address and data for the flash
void latch_addr_and_data(uint32_t addr, uint8_t data) {
	set_addr(addr);
	asm("nop\nnop\n");

	digitalWrite(CE, LOW);
	digitalWrite(WE, LOW);
	asm("nop\nnop\n");

	set_data(data);
	digitalWrite(CE, HIGH);
	digitalWrite(WE, HIGH);
}

// Writes data to the flash at address
void write_to_addr(uint32_t addr, uint8_t data) {
	latch_addr_and_data(0x5555UL, 0xAA);
	latch_addr_and_data(0x2AAAUL, 0x55);
	latch_addr_and_data(0x5555UL, 0xA0);
	latch_addr_and_data(addr, data);

	// spec says 20uS to write the data internally
	delayMicroseconds(20);
}

// Erase the flash chip
void erase_chip() {
	latch_addr_and_data(0x5555UL,0xAA);
	latch_addr_and_data(0x2AAAUL,0x55);
	latch_addr_and_data(0x5555UL,0x80);
	latch_addr_and_data(0x5555UL,0xAA);
	latch_addr_and_data(0x2AAAUL,0x55);
	latch_addr_and_data(0x5555UL,0x10);

	delay(100);
}

// the loop routine runs over and over again forever:
void loop() {
	Serial.write(READY);
	while(!Serial.available());
	Request req = (Request) Serial.read();

	uint8_t data;
	uint32_t addr;
	char buff[10];

	switch(req) {
		case SET_DATA:
			data = (uint8_t) Serial.parseInt();
			set_data(data);
			Serial.write(SUCCESS);
			break;

		case PING:
			Serial.write(PONG);
			break;

		case ERASE:
			if(erase_chip()) {
				Serial.write(SUCCESS);
			} else {
				Serial.write(FAIL);
			}
			break;

		// Sets the address bus to the recieved 16 bit addr
		case SET_ADDR:
			Serial.readBytesUntil('\n', buff, 10);
			sscanf(buff, "%lu", &addr);
			set_addr(addr);
			Serial.write(SUCCESS);
			break;

		default:
			Serial.write(UNKNOWN);
			break;
	}
}
