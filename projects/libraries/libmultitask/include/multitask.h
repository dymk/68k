#ifndef __MULTITASK_H__
#define __MULTITASK_H__

// Creates a new thread of execution
void mt_create_task(void (*task_func)());

//
void mt_enter_critical();
void mt_exit_critical();

/* __MULTITASK_H__ */
#endif
