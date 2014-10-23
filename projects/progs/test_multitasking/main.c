#include "stdlib.h"
#include "io.h"
#include "lcd.h"
#include <stdarg.h>
#include "multitask.h"

static void func();
static void func2();
static void write_til311();

void lcd_putc(void* v, char ch) {
    if(ch == '\n') {
        lcd_cursor(0, 1);
    } else {
        lcd_data(ch);
    }
}

void lcd_printf(char *fmt, ...) {
    va_list va;
    va_start(va,fmt);
    tfp_format(0,&lcd_putc,fmt,va);
    va_end(va);
}

void done() {
    lcd_cursor(0, 0);
    lcd_printf("All threads exited.");
}

uint32_t main() {
    lcd_init();

    lcd_printf("Hello!");
    for(volatile uint32_t i = 0; i < 100000; i++) {}
    lcd_clear();

    mt_enter_critical();
    lcd_printf("Spawning threads...\n");
    mt_exit_critical();

    mt_create_task(func);
    mt_create_task(write_til311);

    on_done(done);

    return 0xAB;
}

void func() {
    // mt_enter_critical();
    // lcd_printf("Calc'ing 500th fib...\n");
    // mt_exit_critical();

    volatile uint32_t a = 0, b = 1;
    for(uint32_t i = 0; i < 100000; i++) {
        uint32_t t = b;
        b = b + a;
        a = t;
    }

    mt_enter_critical();
    lcd_cursor(0, 1);
    lcd_printf("fib: %ld\n", b);
    mt_exit_critical();
}

static void write_til311() {
    for(uint8_t i = 0; i < 0xFF; i++) {
        TIL311 = i;

        for(volatile int c = 0; c < 1000; c++) {}
    }
}
