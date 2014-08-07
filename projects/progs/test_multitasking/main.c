#include "stdlib.h"
#include "multitask.h"

void func();
void func2();

uint32_t main() {
    puts("This is a test, spawning two tasks\n");

    mt_create_task(func);
    mt_create_task(func);
    mt_create_task(func);
    mt_create_task(func);
    mt_create_task(func);
    mt_create_task(func);
    mt_create_task(func);
    mt_create_task(func2);
    mt_create_task(func2);

    return 0xAB;
}

void func() {
    mt_create_task(func2);

    mt_enter_critical();
    puts("entering a super long running task\n");
    mt_exit_critical();

    volatile uint32_t sum = 0;
    for(uint32_t i = 0; i < 20000; i++) {
        sum += i;
    }

    mt_enter_critical();
    printf("Sum of long thing was: %ld\n", sum);
    mt_exit_critical();
}

void func2() {
    mt_enter_critical();
    puts("inside of function 2\n");
    mt_exit_critical();
}
