MEMORY {
    RAM (wx): org = 0x00000, len = 512k
    ROM (rx): org = 0x80000, len = 256k
    IO   (w): org = 0xC0000, len = 256k
}

ENTRY(rom_boot_)

bl_reloc_address = 0x1000;
bl_stack_pointer = ORIGIN(ROM);

SECTIONS {
  /* have the executable relocated to 0x1000, but really start in ROM */
  /* .init(ORIGIN(ROM)) : { */
  .init (bl_reloc_address) : AT (ORIGIN(ROM)) {
    bl_begin = .;
    reloc.o(.data)
    reloc.o(.text)
  } > RAM

  /* include the rest of the loader, which will be executed in RAM */
  .text : ALIGN(4) {
    *(.data)
    *(.text)
    *(.rodata)
    *(.rodata.*)
    bl_end = .;
  } > RAM
}

/* size of the binary in number of longs to copy */
bl_size = (bl_end - bl_begin) / 4;
