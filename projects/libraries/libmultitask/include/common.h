#ifndef __MT_COMMON_H__
#define __MT_COMMON_H__

// opaque pointer to a task, for use by the user
struct mt_task_t;
typedef struct mt_task_t mt_task_t;

// initialize the mt library
void mt_init();

// create a new task
mt_task_t *mt_spawn_task(void (*task_func)(void));

// yield control from the currently executing task
void mt_yield(void);

// wait for a task to complete
void mt_join(mt_task_t *task);

#endif
