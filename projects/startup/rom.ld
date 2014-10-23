stack_size   = DEFINED(stack_size)   ? stack_size : 4096;
__start_func = DEFINED(__start_func) ? __start_func : main;

/* load read/write data starting at 0x2000 */
__data_start_ramloc = 0x2000;

ENTRY(_start)

MEMORY {
    RAM (wx): org = 0x00000, len = 512k
    ROM (rx): org = 0x80000, len = 256k
    IO   (w): org = 0xC0000, len = 256k
}

/* stack grows high mem -> low mem */
__stack_start = ORIGIN(RAM) + LENGTH(RAM);
__stack_end = __stack_start - stack_size;
/* and the end of the heap touches the end of the stack */
__heap_end = __stack_end;

/* define the address of the vector table (ie. base of address space) */
__vectors = 0;

SECTIONS {
  /* startup code must be first in binary, and is given a fixed entry point */
  .startup (0x81000) : ALIGN(0x4) {
    ../../startup/rom.o(.text)
  } > ROM

  /* read only, executable code */
  .text : ALIGN(0x4) {
    *(.text)
  } > ROM

  /* read only data */
  .rodata : ALIGN(0x4) {
    *(.rodata)
    *(.rodata.*)
  } > ROM

  /* force alignment of data being copied into ram */
  . = ALIGN(0x4);
  __data_start_romloc = .;

  /* read/write data, must be loaded into ram by rom.s loader */
  .data (__data_start_ramloc) : ALIGN(0x4) {
    __data_start = .;
    *(.data)
    __data_end = .;
  } > RAM

  /* same with bss */
  .bss(__data_end) : ALIGN(0x4) {
    __bss_start = .;
    *(.bss)
    __bss_end = .;
  } > RAM

  /DISCARD/ : {
    *(.comment)
    *(.debug*)
  }
}

/* data and bss size, in bytes */
__data_longs = (__data_end - __data_start) / 4;
__bss_longs  = (__bss_end  - __bss_start) / 4;

/* start heap after the .bss section */
__heap_start = __bss_end;
__heap_size = __heap_end - __heap_start;
