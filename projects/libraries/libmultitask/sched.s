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

| global scheduler flags; all byets
.set is_swapping,    0x410 | currently in an interrupt, swapping?
.set num_tasks,      0x411 | total number of running tasks
.set __reserved_two, 0x412
.set __reserved_thr, 0x413

| Memory area where task structs reside,
.global task_state_structs
.set task_state_structs,     0x414

| struct task_state_t {
|   uint8_t  state;     // Task state information (currently unused)
|     - bit 0  : in a critical section?
|     - bit 1-7: unused
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
|   uint32_t sp;        // Stack pointer (%a7)
|   uint32_t d[8];      // Data registers
|   uint32_t a[7];      // Address registers
| }
.set ts_offset_state, 0
.set ts_offset_idx,   1
.set ts_offset_flags, 2
.set ts_offset_next,  4
.set ts_offset_stack, 8
.set ts_offset_pc,    12
.set ts_offset_sp,    16
.set ts_offset_d,     20
.set ts_offset_a,     52
.set ts_offset_end,   80

.set ts_status_incrit, 0

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

|.extern init_task_states

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

| Trap codes
.set trap0_code_create_task,    0
.set trap0_code_task_returned,  1
.set trap0_code_enter_critical, 2
.set trap0_code_exit_critical,  3

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

.macro end_trace
  ori.w #0x8000, %sr
.endm
.macro start_trace
  andi.w #0x7FFF, %sr
.endm

.macro sei
    and.w #0xF8FF, %SR
.endm
.macro cli
    ori.w #0x700, %SR
.endm

.macro enable_timer
  ori.b  #0x10, (MFP_IERB)
.endm
.macro disable_timer
  cli
  andi.b #0xCF, (MFP_IERB)
  andi.b #0xCF, (MFP_IMRB)
  sei
.endm

.text
.align 2
| entrypoint for the scheduler, initialize state and execute `main' in
| usermode
.global mt_init_
mt_init_:
  | use GPIO pin 1 as the indicator
  bset.b #1, (MFP_DDR)

  | init serial comms (so host can signal CPU reset)
  move.l #0, -(%sp)
  jsr serial_start
  add.l #4, %sp

  | reference the symbol so it's not dropped by the linker
  move.l #task_stack_start, %d0

  | initialize scheduler state
  move.l #0,            (mt_time)
  move.l #0,            (current_task)
  move.l #0,            (in_use_tasks)
  move.b #0,            (is_swapping)
  move.b #0,            (num_tasks)

  | zero mem and set up linked list of tasks
  jsr init_task_states
  move.l #task_state_structs, (free_tasks)

  | Useful for debugging
  | jsr print_task_states

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
  move.b #184,  (MFP_TDDR)
  ori.b  #0x07, (MFP_TCDCR)
  ori.b  #0x10, (MFP_IMRB)
  enable_timer

  | Start the initial task: main()
  move.b  #trap0_code_create_task, %d0
  movea.l #main, %a0
  trap #0

  | should never reach this
  .extern end_mt_init
  jsr end_mt_init
  illegal

| trap0 handler
| delegates to various other labels to perform common tasks
on_trap0:
  enter_scheduler

  | handler indicator is in %d0
  cmp.b #trap0_code_create_task, %d0
  beq create_task_

  cmp.b #trap0_code_task_returned, %d0
  beq task_return_

  cmp.b #trap0_code_enter_critical, %d0
  beq enter_critical_

  cmp.b #trap0_code_exit_critical, %d0
  beq exit_critical_

  | error, should never fall through this far
  .extern end_on_trap0
  move.l %d0, -(%sp)
  jsr end_on_trap0
  addq.l #4, %sp
  illegal

| Creates task, with entrypoint at %a0, and switches execution to it
| not a subroutine; this should always be branched to
create_task_:
  | if there's already a task running, save its context
  cmp.l #0, (current_task)
  beq _ct_saved_current_task

  | save %a0 as it contains the entrypoint
  move.l %a0, -(%sp)
  move.l (current_task), %a0

  | the saved a0 is going to be basically garbage, although that shouldn't
  | matter, because if there's a current task, it made a function call to
  | trigger create_task_ (via a trap #0)
  movem.l %d0-%d7/%a0-%a6, (%a0, ts_offset_d)

  | CC and PC at 4 and 6, as we incr'd the sp when saving %a0
  move.w (%sp, 4), %d0    | CC and status flags
  move.w %d0, (%a0, ts_offset_flags)
  move.l (%sp, 6), %d0 | PC
  move.l %d0, (%a0, ts_offset_pc)
  move.l %usp, %a1     | SP
  move.l %a1, (%a0, ts_offset_sp)

  move.l (%sp)+, %a0 | restore entrypoint

_ct_saved_current_task:
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
  addq.b #1,  (num_tasks)

  | set up task's program counter and status flags
  move.l %a0, (%a1, ts_offset_pc)
  move.w #0,  (%a1, ts_offset_flags)

  | set up task's stack (with return handler)
  move.l (%a1, ts_offset_stack), %a0
  move.l #task_return, -(%a0)
  move.l %a0, (%a1, ts_offset_sp)

  | move execution to the task
  move.l %a1, %a0
  bra run_task_

| nonfatal, just indicate that there are no more tasks to run
_no_more_tasks:
  disable_timer
  move.l #0, (current_task)

| fatal error label
_fatal_no_more_tasks:
  move.l (mt_time), -(%sp)
  .extern ct_no_more_tasks
  jsr ct_no_more_tasks
  add.l #4, %sp
  illegal

| subroutine for handling a task returning
| tears down current_task, and sets execution to
| the first task in in_use_tasks
task_return:
  | | | | Debugging
  | .extern task_return_debug_msg1
  | jsr task_return_debug_msg1
  move.b #trap0_code_task_returned, %d0
  trap #0

| returned from a task, switch to the next one, and tear this one down
task_return_:
  | find the thing that points to current_task, so it
  | can be set to point to current_task->next
  | lea    (in_use_tasks), %a0 | address pointing to %a1
  move.l  #in_use_tasks, %a0 | address pointing to %a1
  move.l (%a0),          %a1 | task to compare
  move.l (current_task), %a2 | cut down on mem accesses

_tr_find_current_task:
  cmpa.l %a1, %a2
  beq _tr_found_current_task

  | step to next task
  lea.l  (%a1, ts_offset_next), %a0
  move.l (%a0),                 %a1
  bra _tr_find_current_task

_tr_found_current_task:
  | INVARIANT: a1, a2 are equal, and a0 points to a1/a2
  cmp.l (%a0), %a2
  bne _tr_fatal_invariant_failure

  | remove task from in_use_tasks linked list
  move.l (%a2, ts_offset_next), %a1
  move.l %a1, (%a0)
  subq.b  #1, (num_tasks)

  | push onto head of free_tasks linked list
  move.l (free_tasks), %a1
  move.l %a2, (free_tasks)
  move.l %a1, (%a2, ts_offset_next)

  | if there are still tasks, execute the first one
  move.l (in_use_tasks), %a0
  cmpa.l #0, %a0
  beq _no_more_tasks

  | why indeed there is, switch to it
  bra run_task_

  | jumped to on what should be an invariant failure - that %a0 pointed to
  | the address %a1/%a2
_tr_fatal_invariant_failure:
  trap #15
  move.l %a0, -(%sp)
  move.l %a2, -(%sp)
  .extern fatal_invariant_failure
  jsr fatal_invariant_failure
  add.l #8, %sp
  illegal

| Handler for when timer D fires. Typically switches contexts if more than
| one task is currently running, and updates the `mt_time' counter
on_timer_d:

  | incr timer
  |enter_scheduler
  startled_on
  addq.l #1, (mt_time)

  | atomic check if the CPU is already swapping a task
  tas (is_swapping)
  bne _otd_reallyearlyret | early return if we're swapping

  | prevent any other interrupts from happening past this point
  | not required with the `tas' check, and now better time is kept
  | cli

  | we'll need these as scratch space
  movem.l %d0/%a0, -(%sp)

  move.b (num_tasks), %d0
  cmpi.b #1, %d0
  beq _otd_earlyret | only one task running, don't bother with a switch

  | find the next task to execute
  move.l (current_task), %a0
  btst.b #ts_status_incrit, (%a0, ts_offset_state)
  bne _otd_earlyret | return if the task is in a critical section

  | nope, use the first task in in_use_tasks. So now, save the context of the
  | current task. have to restore some registers first.
  move.l (%sp)+,           (%a0, ts_offset_d)
  movem.l %d1-%d7/%a0-%a6, (%a0, ts_offset_d+4) | a0 is going to be jumk
  move.l (%sp)+,           (%a0, ts_offset_a)   | restore old task's a0

  | save flags/pc/sp
  move.w (%sp),    (%a0, ts_offset_flags) | CC and status flags
  move.l (%sp, 2), (%a0, ts_offset_pc)    | PC
  move.l %usp,      %a1                   | SP
  move.l %a1,      (%a0, ts_offset_sp)

  | alright, context saved, and current task is in %a0
  | get the next task to run
  move.l (%a0, ts_offset_next), %a0
  cmpa.l #0, %a0
  bne run_task_

  | was at end of in use tasks linked list; go back to front
  move.l (in_use_tasks), %a0

| loads a task's context and returns into it
| not a subroutine, should be jumped to directly
| expects task to switch to in %a0
run_task_:
  move.l %a0, (current_task)

  | set up status, pc, and sp regs
  move.w (%a0, ts_offset_flags), (%sp)    | CC and status
  move.l (%a0, ts_offset_pc),    (%sp, 2) | PC
  move.l (%a0, ts_offset_sp), %a1         | SP
  move.l %a1, %usp

  | restore registers
  movem.l (%a0, ts_offset_d), %d0-%d7/%a0-%a6

  | done, `rte' to execute task, and clear swapping flag
  clr.b (is_swapping)
  ret_from_scheduler

_otd_earlyret:
  movem.l (%sp)+, %d0/%a0
  clr.b (is_swapping)

_otd_reallyearlyret:
  ret_from_scheduler

|.global init_task_states
init_task_states:
  move.l %a2, -(%sp)

  | for now, zero all task status memory
  move.l #task_state_structs, %a0
  move.l #total_ts_size,      %d0
  subq.l #1, %d0

  | zero out all task struct memory
_its_clear:
  move.b #0, (%a0)+
  dbra %d0, _its_clear

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

enter_critical_:
  move.l (current_task), %a0
  bset.b #ts_status_incrit, (%a0, ts_offset_state)
  ret_from_scheduler

exit_critical_:
  move.l (current_task), %a0
  bclr.b #ts_status_incrit, (%a0, ts_offset_state)
  ret_from_scheduler

.global mt_enter_critical
mt_enter_critical:
  move.b #trap0_code_enter_critical, %d0
  trap #0
  rts

.global mt_exit_critical
mt_exit_critical:
  move.b #trap0_code_exit_critical, %d0
  trap #0
  rts

| C abi compatible, usermode function to spawn a new task
| and begin its execution
.global mt_create_task
mt_create_task:
  move.l (%sp, 4), %a0
  move.b #trap0_code_create_task, %d0
  trap #0
  rts
