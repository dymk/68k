stack_size   = DEFINED(stack_size) ? stack_size : 4096;
__start_func = DEFINED(__start_func) ? __start_func : main;

ENTRY(_start)

MEMORY {
    RAM (wx): org = 0x00000, len = 512k
    ROM (rx): org = 0x80000, len = 256k
    IO   (w): org = 0xC0000, len = 256k
}

__stack_start = ORIGIN(RAM) + LENGTH(RAM);
__stack_end = __stack_start - stack_size;
__heap_end = __stack_end;

/* define the address of the vector table (ie. base of address space) */
__vectors = 0;

SECTIONS {
  /* startup code must be first in binary, given 0x2000 as fixed entry point */
  .startup (0x2000) : {
    ../../startup/ram.o(.text)
  } > RAM

  .text : ALIGN(0x4) {
    __text_start = .;
    *(.text)
    __text_end = .;
  } > RAM

  .data : ALIGN(0x4) {
    __data_start = .;
    *(.data)
    *(.rodata)
    *(.rodata.*)
    __data_end = .;
  } > RAM

  .bss : ALIGN(0x4) {
    __bss_start = .;
    *(.bss)
    __bss_end = .;
  } > RAM

  /DISCARD/ : {
    *(.comment)
    *(.debug*)
  }
}

__heap_start = __bss_end;
__heap_size = __heap_end - __heap_start;
__bss_size  = (__bss_end - __bss_start) / 4;
