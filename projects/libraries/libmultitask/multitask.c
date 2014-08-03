#include "multitask_private.h"

__attribute__((packed))
struct mt_task_t {
    void (*task_func)(void);
};

// datastructures private to the mt library
extern volatile uint32_t mt_time;
extern volatile mt_task_t *current_task;
