#include "stdlib.h"
#include "multitask.h"

void func();

uint32_t main() {
    puts("This is a test, spawning two tasks\n");

    mt_create_task(func);
    mt_create_task(func);

    return 0xAB;
}

void func() {
    mt_enter_critical();
    puts("entering a super long running task\n");
    mt_exit_critical();

    volatile uint32_t sum = 0;
    for(uint32_t i = 0; i < 100000; i++) {
        sum += i;
    }

    mt_enter_critical();
    puts("exiting a super long running task\n");
    // putc(constrain(sum, '0', '9'));
    // putc('\n');
    mt_exit_critical();
}
