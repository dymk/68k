# 68008 executable basic makefile

####### VARIABLES #######

ifndef PRJ
    PRJ = $(notdir $(CURDIR))
endif

ifndef BIN
    BIN = $(PRJ).s68
endif

ifndef OPTIMIZE
    OPTIMIZE = 3
endif

# RAM or ROM
ifndef CODE_LOC
    CODE_LOC = ram
else
    # convert to lower
    CODE_LOC := $(shell echo $(CODE_LOC) | tr A-Z a-z)
endif

ifeq ($(CODE_LOC),rom)
    ULFLAGS += -f
endif

ifdef USE_MULTITASK
    LIBS+= -lmultitask
    LDFLAGS += --defsym "__start_func=_kernel_start"
endif

ifndef NO_CORELIB
    LIBS += -lcore -lgcc
endif

STARTUP_SRC = ../../startup/$(CODE_LOC).s
STARTUP_OBJ = ../../startup/$(CODE_LOC).o
ifndef NO_STARTUP
    OBJS += $(STARTUP_OBJ)
endif

ifndef LINK_SCRIPT
    LINK_SCRIPT = ../../startup/$(CODE_LOC).ld
endif

# Program names

RM      = rm -f
CC      = m68k-elf-gcc
LD      = m68k-elf-ld
AS      = m68k-elf-as
OBJDUMP = m68k-elf-objdump
OBJCOPY = m68k-elf-objcopy

SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
include $(SELF_DIR)/common.mk

CFLAGS  += -O$(OPTIMIZE) -nostartfiles -nostdinc -nostdlib -m68000 -std=c99 -Wall -pedantic -fno-builtin $(INCPATHS)
LDFLAGS += -nostartfiles -nostdlib -A m68000 -T $(LINK_SCRIPT) $(LIBPATHS) --oformat srec
ASFLAGS += -march=68000 -mcpu=68000

# clear suffixes
.SUFFIXES:
.SUFFIXES: .c .o .lst .s

####### TARGETS ########

all:	$(BIN)

clean:
	$(RM) $(OBJS) $(BIN) $(LSTS) $(PRJ).bin $(PRJ).l68 $(PRJ).map

commit:
	git diff
	git add .
	git commit -a

# Open source in default editor, on mac.
open:
	-edit $(SRC_C) $(SRC_S) Makefile

run:	$(BIN)
ifeq ($(CODE_LOC),rom)
	@echo ERROR: Can only upload a ROM project!
else
	../../../uploader/uploader $(PRJ).bin
endif

upload: $(BIN)
	../../../srec2srb/srec2srb $(BIN) /tmp/_$(PRJ).srb
	../../../uploader/uploader -x -b -s $(ULFLAGS) /tmp/_$(PRJ).srb

listing: $(LSTS)

$(BIN): $(OBJS)
	$(LD)  $(OBJS) $(LIBS) $(LDFLAGS) -o $(BIN) -Map $(PRJ).map
	$(OBJCOPY) -I srec $(BIN) -O binary $(PRJ).bin
	$(OBJDUMP) -D $(BIN) -m68000 > $(PRJ).l68
	@echo
	@echo -n 'Binary size: '
	@stat -f %z $(PRJ).bin | sed 's/$$/ bytes/'

.s.o:
	$(AS) $(ASFLAGS) -o $@ $<

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

.c.lst:
	$(CC) $(CFLAGS) -c -S -o $@ $<
