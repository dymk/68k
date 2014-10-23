#ifndef __MULTITASK_H__
#define __MULTITASK_H__

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

extern const task_state_t task_states[38];
extern const task_state_t *current_task;
extern const task_state_t *free_tasks;
extern const task_state_t *in_use_tasks;

// Creates a new thread of execution
void mt_create_task(void (*task_func)());

// If a task is in a critical section, the scheduler will not
// swap it out
void mt_enter_critical();
void mt_exit_critical();

// callback for when all tasks finish
void on_done(void (*done)(void));

/* __MULTITASK_H__ */
#endif
