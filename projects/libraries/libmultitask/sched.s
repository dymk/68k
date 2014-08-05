| scheduler.s: multitasking scheduler for the 68k
| Free space can be found from 0x400 to 0x1000
| (from end of vector table up to the bootloader)

| I/O addresses
.set IO_BASE,  0xC0000
.set MFP_BASE, IO_BASE
.set MFP_GPDR, MFP_BASE + 0x01 | gpio data reg
.set MFP_DDR,  MFP_BASE + 0x05 | gpio data direction
.set MFP_IERB, MFP_BASE + 0x09 | interrupt enable register, b
.set MFP_IMRB, MFP_BASE + 0x15 | interrupt mask register, b
.set MFP_TDDR, MFP_BASE + 0x25 | timer d data register
.set MFP_TCDCR,MFP_BASE + 0x1D | timer c & d control register
.set MFP_VR,   MFP_BASE + 0x17 | vector register (high nibble of vector number)


.set TIL311, IO_BASE + 0x8000

.extern puts
.extern putc
.extern putc_sync
.extern main
.extern serial_start

.extern MFP_VR_VAL

| scheduler timer (longword)
.global mt_time
.set mt_time, 0x400

| pointer to currently scheduled task (longword)
.set current_task, 0x404

| Pointer to the list of free task structs
.set free_tasks,   0x408

| Task structs, used to tracking current task state
.set task_states,     0x40C

| struct task_state_t {
|   uint8_t  state;     // Task state information (currently unused)
|     - bit 0-7: unused
|   uint8_t  task_idx;  // Quick lookup of this task's index in the struct array
|   uint16_t flags;     // status/CC flags
|
|   uint8_t _padding[1];
|
|   // Pointer to next task in the list (last is null)
|   uint32_t next;
|
|   // Pointer to the base of the stack frame for the task
|   uint32_t stack;
|
|   uint32_t pc;        // Program counter
|   uint32_t d[8];      // Data registers
|   uint32_t a[7];      // Address registers
|   uint32_t sp;        // Stack pointer (%a7)
| }
.set ts_offset_state, 0
.set ts_offset_idx,   1
.set ts_offset_flags, 2
.set ts_offset_next,  4
.set ts_offset_stack, 8
.set ts_offset_pc,    12
.set ts_offset_d,     16
.set ts_offset_a,     48
.set ts_offset_sp,    76
.set ts_offset_end,   80
| total size (ts_offset_end): 80 (0x4C) bytes


| 38 task structs total (at 80 bytes per task state struct)
.set max_num_tasks, (0x1000 - task_states) / ts_offset_end

| 4096 default stack size (including the kernel)
.set task_stack_size,  0x1000
.extern __stack_start
.set task_stack_start, __stack_start - task_stack_size

| Options that on_trap0 responds to
| with args in %d0 and %a0
.set TRAP_CREATE_TASK, 0
.set TRAP_TASK_RETURNED, 1
| not implemented yet
| .set TRAP_YIELD,       2

.data
.align 1
.macro put_str str
  lea (%pc,\str), %a0
  move.l %a0, -(%sp)
  bsr puts
  addq.l #4, %sp
.endm
.macro put_char chr
  move.l #\chr, -(%sp)
  bsr putc
  addq.l #4, %sp
.endm

.macro statled_on
  bset.b #1, (MFP_GPDR)
.endm
.macro statled_off
  bclr.b #1, (MFP_GPDR)
.endm

.macro ret_from_scheduler
  statled_off
  sei
  rte
.endm

.macro sei
    and.w #0xF8FF, %SR
.endm
.macro cli
    ori.w #0x700, %SR
.endm

| Format strs
illegal_trapcode_fmt_str: .asciz "Illegal multitask trapcode used: %d\n"
no_more_tasks_fmt_str:    .asciz "Reached maximum number of tasks: %d\n"
print_task_base_fmt_str:  .asciz "Task with IDX %d (addr $%lx) has stack base: $%lx, next task: $%lx\n"
done_with_life_fmt_str:   .asciz "Done with all tasks, looping forever\n"

.text
.align 2
| entrypoint for the scheduler, initialize state and execute `main' in
| usermode
.global mt_init_
mt_init_:

  | start serial comms
  move.l #0, -(%sp)
  jsr serial_start
  addq.l #4, %sp

  | use GPIO pin 1 as the indicator
  bset.b #1, (MFP_DDR)

  move.b #0xA1, (TIL311)

  | initialize scheduler state
  move.l #0,           (mt_time)
  move.l #0,           (current_task)
  move.l #task_states, (free_tasks)
  jsr init_task_structs
  | jsr inspect_task_state

  move.b #0xA2, (TIL311)

  | install handler for timer D vector
  | timer D's low nibble is 0x4, so MFP_VR | (timer d) = 0x44
  | so install handler at (0x44 * 4)
  move.l  #0, %d0
  move.b  (MFP_VR), %d0
  addq.l  #0x4, %d0
  lsl.l   #0x2, %d0
  movea.l %d0,  %a0
  move.l  #on_timer_d, (%a0)

  | install trap 0 vector
  move.l #on_trap0, 0x80

  | initialize timer D to drive millis_vect
  | 3.6864mhz, 200 prescaler, 184 data is ~ a 100hz interrupt
  move.b #255,  (MFP_TDDR)
  ori.b  #0x07, (MFP_TCDCR)
  ori.b  #0x10, (MFP_IMRB)
  ori.b  #0x10, (MFP_IERB)

  move.b #0xA4, (TIL311)

  | Start the initial task: main()
  movea.l #main, %a0
  move.b  #TRAP_CREATE_TASK, %d0
  trap #0

  | should never reach this
  illegal

| handler for timer D interrupt
on_timer_d:
  statled_on
  cli

  | save current task's a0
  move.l %a0, -(%sp)
  move.l (current_task), %a0

  | no more tasks, just return
  cmpa.l #0, %a0
  bne _otd_have_current_task
  addq.l #4, %sp
  move.b #0xAD, (TIL311)
  bra _forever

_otd_have_current_task:
  | save the current context
  movem.l %d0-%d7/%a0-%a6, (%a0, ts_offset_d) | save regs, a0 won't be correct
  move.l (%sp)+,           (%a0, ts_offset_a) | save the correct a0

  move.w (%sp), %d0
  move.w %d0, (%a0, ts_offset_flags) | flags

  move.l (%sp, 2), %d0
  move.l %d0, (%a0, ts_offset_pc)    | PC

  move.l %usp, %a1
  move.l %a1, (%a0, ts_offset_sp)    | SP

  | get next task to switch to
  move.l (%a0, ts_offset_next), %a1
  cmpa.l #0, %a1
  beq _otd_at_last_task

  | not at last task, set %a0 to next task
  move.l (%a0, ts_offset_next), %a0

  bra _otd_found_next_task

_otd_at_last_task:
  | at the last task in the list, set current_task to first task
  move.l (task_states), %a0

_otd_found_next_task:
  move.l %a0, (current_task)
  move.l %a0, %a1
  bra switch_to_current_task_

| handler for trap0; e.g.
on_trap0:
  | don't interrupt while changing scheduler state
  | means handlers must set or use ret_from_scheduler
  cli
  move.b #0xA5, (TIL311)

  cmp.b #TRAP_CREATE_TASK, %d0
  beq create_task_
  cmp.b #TRAP_TASK_RETURNED, %d0
  beq task_returned_

  move.l %d0, -(%sp)
  move.l #illegal_trapcode_fmt_str, -(%sp)
  jsr printf
  addq.l #8, %sp
  bra _forever

| Just loop. Forever. We'll never leave the comfort of the loop.
_forever: bra _forever

| C abi compatible task creation routine
mt_create_task:
  | entrypoint is the first param passed
  movea.l (%sp, 4),          %a0
  move.b  #TRAP_CREATE_TASK, %d0
  trap #0
  rts

| Creates a new task
| New task entrypoint in %a0
create_task_:
  | grab a struct from the freelist
  movea.l (free_tasks), %a1
  cmpa.l #0, %a1
  bne _ct_has_free_task

  | no more free tasks, display an error message
  move.l #max_num_tasks, -(%sp)
  move.l #no_more_tasks_fmt_str, -(%sp)
  jsr printf
  addq.l #4, %sp
  move.b #0xE0, (TIL311)
  bra _forever

_ct_has_free_task:
  | pop the free task off of the free_tasks list
  move.l (%a1, ts_offset_next), %d0
  move.l  %d0, (free_tasks)

  | push it on the front of the used tasks list
  move.l (task_states), %d0 | save running tasks list head
  move.l %d0, (%a1, ts_offset_next) | set task's next pointer
  move.l %a1, (task_states) | set task at the head of active tasks list

  | set new task's sp, pc, and flags
  move.l %a2, -(%sp)
  move.l (%a1, ts_offset_stack), %a2
  move.l #on_task_return_, -(%a2) | subroutine the task returns to
  move.l (%sp)+, %a2

  move.l %a2, (%a1, ts_offset_sp)    | SP
  move.l %a0, (%a1, ts_offset_pc)    | PC
  move.w #0,  (%a1, ts_offset_flags) | CC and status flags

  | set as the current running task
  move.l %a1, (current_task)

  | run the new task
  bra switch_to_current_task_

| Move context to the current task
| this should be jumped to directly, not called like a subroute
| Expects the current task in %a1
switch_to_current_task_:
  | restore PC
  move.l (%a1, ts_offset_pc), %a0
  move.l %a0, (%sp, 2)

  | restore CC/status flags
  move.w (%a1, ts_offset_flags), %d0
  move.w %d0, (%sp)

  | restore USP
  move.l (%a1, ts_offset_sp), %a0
  move.l %a0, %usp

  | restore all registers
  movem.l (%a1, ts_offset_d), %d0-%d7/%a0-%a6

  ret_from_scheduler

| Function that tasks return to after returning
| Just springboards into supervisor mode, and from there task_returned
on_task_return_:
  move #TRAP_TASK_RETURNED, %d0
  trap #0

| handles task returning (in supervisor mode)
task_returned_:
  move.l %a2, -(%sp)
  | find where 'current_task' is in the free tasks list
  | %a0: task in the list being inspected
  | %a1: the pointee to %a0
  | %a2: addr of current task
  move.l (task_states),  %a0
  move.l #task_states,   %a1
  move.l (current_task), %a2

_otr_check_if_found_ct:
  cmpa.l %a2, %a0
  beq _otr_found_current_task

  | nope, to to the next task
  movea.l  %a0, %a1
  movea.l (%a0, ts_offset_next), %a0
  bra _otr_check_if_found_ct

_otr_found_current_task:
  | INVARIANT: %a0 must equal (current_task), %a2
  | a0: -> current_task
  | a1: -> pointer to current_task

  | set the pointee to point to the current task's next pointer
  move.l (%a0, ts_offset_next), %a2
  move.l %a2, (%a1, ts_offset_next)

  | set the finished task's next pointer as the current task
  | if null, set it to #task_states
  cmpa.l #0, %a2
  bne _otr_set_new_current_task

  | was the last task, set current task to head of tasks list
  move.l #task_states, %a2

_otr_set_new_current_task:
  move.l %a2, (current_task)

  | push finished task to the front of the free tasks list
  move.l (free_tasks), %d0
  move.l %d0, (%a0, ts_offset_next)
  move.l %a0, (free_tasks)

  | are there any more tasks to run anyways?
  cmpa.l #0, %a2
  bne _otr_run_swapped

  | nope, just loop forever
  cli
  move.b #0xAC, (TIL311)
  bra _forever

_otr_run_swapped:
  move.l (%sp)+, %a2
  put_str done_with_life_fmt_str

  | switch context to the current task
  bra switch_to_current_task_


| Initialize the task's doubly linked list structure
init_task_structs:
  move.l %a2, -(%sp)

  | for now, zero all task status memory
  move.l #3053, %d0
  movea.l #task_states, %a0

_zero_loop:
  move.b #0, (%a0)
  adda.l #1,  %a0
  dbra %d0, _zero_loop

  movea.l #task_states, %a0

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

inspect_task_state:
  | lets inspect the structs for fun
  move.l %a2, -(%sp)
  movea.l (free_tasks), %a2
_its_start_inspect:
  cmpa.l #0, %a2
  beq _its_end_inspect

  movea.l (%a2, ts_offset_next), %a0   | next task addr
  move.l %a0, -(%sp)
  move.l (%a2, ts_offset_stack), %d0  | stack base addr
  move.l %d0, -(%sp)
  move.l %a2, -(%sp)                  | this task addr
  clr.l %d0                           | task index number
  move.b (%a2, ts_offset_idx), %d0
  move.l %d0, -(%sp)

  move.l #print_task_base_fmt_str, -(%sp)
  jsr printf
  adda.l #20, %sp

  movea.l (%a2, ts_offset_next), %a2
  bra _its_start_inspect
_its_end_inspect:
  move.l (%sp)+, %a2

  rts
