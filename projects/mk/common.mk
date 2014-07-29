# Common include dir and lib paths
INCPATHS += -I. -I../../include
LIBPATHS += -L../../lib

# inc/lib paths specific to my cross compiler installation
INCPATHS += -I/Users/dymk/code/c/toolchain/68k/lib/gcc/m68k-elf/4.2.4/include/
LIBPATHS += -L/Users/dymk/code/c/toolchain/68k/lib/gcc/m68k-elf/4.2.4/m68000/
