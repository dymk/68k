#include "stdlib.h"
#include "string.h"
#include "stdio.h"
#include "multitask.h"

static void(*on_done_func)(void) = NULL;
void on_done(void (*done)(void)) {
    on_done_func = on_done;
}

void end_mt_init() {
    puts("Error, mt_init_ reached end. halting.\n");
    while(true) {}
}
void end_on_trap0(uint8_t num) {
    puts("invalid trap 0 call: ");
    putc(num + '0');
    puts(". halting.\n");

    while(true) {}
}
void ct_no_more_tasks(uint32_t millis) {
    printf("All threads exited. Halting. (millis counter: %ld)\n", millis);
    if(on_done_func) {
        printf("Running finished func\n");
        on_done_func();
    }
    while(true) {}
}
void fatal_invariant_failure(uint32_t task_ptr, uint32_t task_pointee) {
    printf("task at $%lx wasn't pointed to from $%lx\n");
}
void print_task_states() {
    printf("task states: \n");
    task_state_t *task = free_tasks;
    while(task) {
        printf("Task id: %d, addr: $%lx, next: $%lx\n", task->task_idx, task, task->next);
        task = task->next;
    }
}
// void task_return_debug_msg1() {
//     puts("A task returned\n");
// }
// void task_return_debug_msg2() {
//     puts("there's a task in in_use_tasks list, using that\n");
// }
// void debug_switched_task(uint32_t from, uint32_t to) {
//     printf("\n$%lx -> $%lx\n", from, to);
// }
