#include "loader.h"
#include "lcd.h"

// Address to write the loaded program to
static uint8_t *write_to, *jump_to;
static LOADER_FLAGS flags;

void loader_start() {
    lcd_init();

    TIL311 = 0x02;

    // reset timer C
    TCDCR &= 0x0F;

    // trigger every other tick
    TCDR = 1;

    // enable C timer with /4 prescaler
    TCDCR |= 0x10; // 0b00010000

    // set up USART
    // /16, 8 bit word, 1 stop bit, no parity
    UCR = 0x88; // 0b10001000

    // Enable reciever/transmitter
    RSR = 1;
    TSR = 1;

    TIL311 = 0x03;

    // initialize with default location
    jump_to  = DEFAULT_ADDRESS;
    write_to = DEFAULT_ADDRESS;

    lcd_puts("Ready to recieve");

    uint8_t recieved = 0;

    // main bootloader loop
    while(true) {

        uint8_t byte = getc();
        TIL311 = byte;

        if(!(GPDR & 1)) {
            command((COMMAND) byte);
        }
        else {
            // write to address
            (*write_to++) = byte;

            // echo back out to user
            putc(byte);
        }

        if(!recieved) {
            recieved = 1;
            lcd_puts("Programming...");
        }
    }
}

void command(COMMAND cmd)
{
    switch(cmd) {
    case CMD_SET_FLWR:  flags |= LF_WRITE_FLASH; break;
    case CMD_SET_LDWR:  flags |= LF_WRITE_LOADER; break;
    case CMD_SET_BINSR: flags |= LF_IS_BINSREC; break;
    case CMD_BOOT:
        lcd_puts("Booting in");

        DELAY_MS(500);
        lcd_puts("3...");

        DELAY_MS(500);
        lcd_puts("2...");

        DELAY_MS(500);
        lcd_puts("1...");

        __asm volatile("jmp (%0)\n"::"a"(jump_to));
        break;
    }
}

void putc(uint8_t byte) {
    while(!(TSR & (1 << 7))) {}
    UDR = byte;
}

uint8_t getc() {
    while(!(RSR & (1 << 7))) {}
    return UDR;
}
