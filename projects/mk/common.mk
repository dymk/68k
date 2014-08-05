# add the 'include' directory for all libs
INCPATHS += $(foreach \
	dir, \
	$(wildcard ../../libraries/lib*/include), \
	-I$(dir))

# Common include dir and lib paths
INCPATHS += -I . -I ../../include
LIBPATHS += -L ../../lib

# inc/lib paths specific to my cross compiler installation
INCPATHS += -I /Users/dymk/code/c/toolchain/68k/lib/gcc/m68k-elf/4.2.4/include/
LIBPATHS += -L /Users/dymk/code/c/toolchain/68k/lib/gcc/m68k-elf/4.2.4/m68000/
CFLAGS   += -fno-pic -O3 -nostartfiles -nostdinc -nostdlib -m68000 -std=c99 -fno-builtin $(INCPATHS)
ASFLAGS  += -march=68000 -mcpu=68000

# List of source files
SRC_C = $(wildcard *.c)
SRC_S = $(wildcard *.s)

OBJS += $(SRC_C:.c=.o) $(SRC_S:.s=.o)
LSTS  = $(SRC_C:.c=.lst)

