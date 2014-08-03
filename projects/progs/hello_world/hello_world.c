#include "stdlib.h"
#include "serial.h"
#include "printf.h"
#include "io.h"
#include "lcd.h"

int main() {
    serial_start(SERIAL_SAFE);
    lcd_init();
    lcd_clear();

    lcd_puts("Hello, world!");

    while(true) {
        for(int i = 0; i < 255; i++) {
            TIL311 = i;
            printf("i was: %d\n", i);
            DELAY_MS(10);
        }
    }

    return 0;
}
