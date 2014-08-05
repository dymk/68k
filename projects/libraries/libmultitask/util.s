.align 2
.text

| Initialize the linked list of tasks
.extern ts_offset_end
.extern ts_offset_idx
.extern ts_offset_next
.extern ts_offset_stack
.extern max_num_tasks
.extern task_stack_start
.extern total_ts_size
.extern task_stack_size
.extern task_state_structs
.extern memset

.global init_task_states
init_task_states:
  move.l %a2, -(%sp)

  | for now, zero all task status memory
  move.l #task_state_structs, -(%sp)
  move.l #0,                  -(%sp)
  move.l #total_ts_size,      -(%sp)
  jsr memset
  add.l #12, %sp

  movea.l #task_state_structs, %a0

  move.l  #0, %d1 | loop index counter
  move.l  #max_num_tasks, %d0
  subq.l  #1, %d0

  | base of the first task's stack
  movea.l #task_stack_start, %a2

_init_task_state:
  | initialize linked list of states
  movea.l %a0, %a1
  adda.w #ts_offset_end, %a1 | next pointer
  move.l %a1, (%a0, ts_offset_next)

  | set task index and stack starting position
  move.b %d1, (%a0, ts_offset_idx)
  move.l %a2, (%a0, ts_offset_stack)

  | advance to next task state struct, idx, and stack position
  adda.l #ts_offset_end, %a0
  addq.b #1, %d1
  suba.l #task_stack_size, %a2

  | end loop
  dbra %d0, _init_task_state

  | nullify last task's next pointer
  suba.l #ts_offset_end, %a0
  move.l #0, (%a0, ts_offset_next)

  move.l (%sp)+, %a2
  rts
