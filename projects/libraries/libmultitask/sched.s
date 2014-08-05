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
.global current_task
.set current_task, 0x404

| Pointer to the list of free task structs
.global free_tasks
.set free_tasks,   0x408

| List of tasks already in use
.global in_use_tasks
.set in_use_tasks, 0x40C

| Memory area where task structs reside,
.global task_state_structs
.set task_state_structs,     0x410

| struct task_state_t {
|   uint8_t  state;     // Task state information (currently unused)
|     - bit 0-7: unused
|   uint8_t  task_idx;  // Quick lookup of this task's index in the struct array
|   uint16_t flags;     // status/CC flags
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

.global ts_offset_state
.global ts_offset_idx
.global ts_offset_flags
.global ts_offset_next
.global ts_offset_stack
.global ts_offset_pc
.global ts_offset_d
.global ts_offset_a
.global ts_offset_sp
.global ts_offset_end

.extern init_task_states

| 38 task structs total (at 80 bytes per task state struct)
.global max_num_tasks
.set max_num_tasks, (0x1000 - task_state_structs) / ts_offset_end

| 4096 default stack size (including the kernel)
.set task_stack_size,  0x1000
| using this seems to cause the linker to not see task_stack_start
| .extern __stack_start
| .set task_stack_start, __stack_start-task_stack_size
.set task_stack_start, 0x80000-task_stack_size
.set total_ts_size, max_num_tasks*ts_offset_end

.global task_stack_size
.global total_ts_size
.global task_stack_start

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

.macro startled_on
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
.macro enter_scheduler
  startled_on
  cli
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

  | reference the symbol so it's not dropped by the linker
  move.l #task_stack_start, %d0

  | initialize scheduler state
  move.l #0,            (mt_time)
  move.l #0,            (current_task)
  move.l #0,            (in_use_tasks)
  jsr init_task_states
  move.l #task_state_structs, (free_tasks)

  | jsr print_task_states

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
  move.b  #trap0_code_create_task, %d0
  movea.l #main, %a0
  trap #0

  | should never reach this
  .extern end_mt_init
  jsr end_mt_init
  illegal

on_timer_d:
  enter_scheduler
  | currently just noop
  ret_from_scheduler

.set trap0_code_create_task,   0
.set trap0_code_task_returned, 1

| trap0 handler
| delegates to various other labels to perform common tasks
on_trap0:
  enter_scheduler

  | handler indicator is in %d0
  cmp.b #trap0_code_create_task, %d0
  bra create_task_

  cmp.b #trap0_code_task_returned, %d0
  bra task_return_

  .extern end_on_trap0
  move.l %d0, -(%sp)
  jsr end_on_trap0
  addq.l #4, %sp
  illegal

| Creates task, with entrypoint at %a0, and switches execution to it
| not a subroutine; this should always be branched to
create_task_:

  | acquire a free task
  move.l (free_tasks), %a1
  cmpa.l #0, %a1
  beq _fatal_no_more_tasks

  | pop from front of the free tasks list
  move.l (%a1, ts_offset_next), %d2
  move.l %d2, (free_tasks)

  | push to front of in use list
  move.l (in_use_tasks), %d2
  move.l %a1, (in_use_tasks)
  move.l %d2, (%a1, ts_offset_next)

  | set up task's program counter
  move.l %a0, (%a1, ts_offset_pc)

  | set up task's stack (with return handler)
  move.l (%a1, ts_offset_stack), %a0
  move.l #task_return, -(%a0)
  move.l %a0, (%a1, ts_offset_sp)

  | move execution to the task
  move.l %a1, %a0
  bra run_task_

| loads a task's context and returns into it
| not a subroutine, should be jumped to directly
| expects task to switch to in %a0
run_task_:
  move.l %a0, (current_task)

  | set up status, pc, and sp regs
  move.w (%a0, ts_offset_flags), %d0
  move.w %d0, (%sp)    | CC and status
  move.l (%a0, ts_offset_pc), %d0
  move.l %d0, (%sp, 2) | PC
  move.l (%a0, ts_offset_sp), %a1
  move.l %a1, %usp     | SP

  | restore registers
  movem.l (%a0, ts_offset_d), %d0-%d7/%a0-%a6

  | done, `rte' to execute task
  ret_from_scheduler

| fatal error label
_fatal_no_more_tasks:
  .extern ct_no_more_tasks
  jsr ct_no_more_tasks
  illegal

| subroutine for handling a task returning
| tears down current_task, and sets execution to
| the first task in in_use_tasks
task_return:
  .extern task_return_debug_msg
  jsr task_return_debug_msg

  move.b #trap0_code_task_returned, %d0
  trap #0

| returned from a task, switch to the next one, and tear this one down
task_return_:

  move.l %a2, -(%sp)         | save a2
  | find the thing that points to current_task, so it
  | can be set to point to current_task->next
  | lea    (in_use_tasks), %a0 | address pointing to %a1
  move.l  #in_use_tasks, %a0 | address pointing to %a1
  move.l (%a0),          %a1 | task to compare
  move.l (current_task), %a2 | cut down on mem accesses

  cmpa.l %a1, %a2
  beq _tr_found_current_task

  | step to next task
  | lea.l  (%a1, ts_offset_next), %a0
  movea.l %a1, %a0
  adda.l  #ts_offset_next, %a0
  move.l (%a0),            %a1

_tr_found_current_task:
  | INVARIANT: a1, a2 are equal, a0's value is the address of the memory
  | location that points to a1/a2's value

  | remove task from in_use_tasks linked list
  move.l (%a2, ts_offset_next), %a1
  move.l %a1, (%a0)

  | push onto head of free_tasks linked list
  move.l (free_tasks), %a1
  move.l %a2, (free_tasks)
  move.l %a1, (%a2, ts_offset_next)

  move.l (%sp)+, %a2         | restore a2

  | if there are still tasks, execute the first one
  move.l (in_use_tasks), %a0
  cmpa.l #0, %a0
  beq _fatal_no_more_tasks

  | why indeed there is, execute it
  bra run_task_

