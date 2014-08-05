#include "stdlib.h"
#include "string.h"
#include "stdio.h"
#include "multitask.h"

typedef struct __attribute__((packed)) {
    uint8_t  state;     // Task state information (currently unused)
    uint8_t  task_idx;  // Quick lookup of this task's index in the struct array
    uint16_t flags;     // status/CC flags

    // Pointer to next task in the list (last is null)
    void *next;

    // Pointer to the base of the stack frame for the task
    uint32_t stack;

    uint32_t pc;        // Program counter
    uint32_t d[8];      // Data registers
    uint32_t a[7];      // Address registers
    uint32_t sp;        // Stack pointer (%a7)
} task_state_t;

extern task_state_t task_states[38];
extern task_state_t *current_task;
extern task_state_t *free_tasks;
extern task_state_t *in_use_tasks;

void print_task_states() {
    printf("task states: \n");
    task_state_t *task = free_tasks;
    while(task) {
        printf("Task id: %d, addr: $%lx, next: $%lx\n", task->task_idx, task, task->next);
        task = task->next;
    }
}

void end_mt_init() {
    printf("mt_init_ reached end. halting.");
    while(true) {}
}
void end_on_trap0(uint8_t num) {
    printf("invalid trap 0 call: %d. halting.\n", num);
    while(true) {}
}
void ct_no_more_tasks() {
    printf("No more tasks in list! halting.");
    while(true) {}
}
void task_return_debug_msg() {
    printf("Task returned, running trap 0\n");
}
void task_return_debug_msg2(uint32_t task_addr) {
    printf("Another task is going to run: %lx\n", task_addr);
}
