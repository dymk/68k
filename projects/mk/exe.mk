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


_STARTUP_SRC = ../../startup/$(CODE_LOC).s
_STARTUP_OBJ = ../../startup/$(CODE_LOC).o
ifndef NO_STARTUP
    OBJS += $(_STARTUP_OBJ)
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

ifdef USE_MULTITASK
    LIBS+= --whole-archive -lmultitask  --no-whole-archive
    LDFLAGS += --defsym "__start_func=mt_init_"
endif

ifndef NO_CORELIB
    LIBS += -lcore -lgcc
endif

ifndef LINK_SCRIPT
    LINK_SCRIPT = ../../startup/$(CODE_LOC).ld
    LDFLAGS += -T $(LINK_SCRIPT)
endif

LDFLAGS += -nostartfiles -nostdlib -A m68000 --oformat srec

# clear suffixes
.SUFFIXES:
.SUFFIXES: .c .o .lst .s

# all libraries that will be passed to the linker, with the `-l' trimmed off
_ALL_LIBNAMES   = $(subst -l,,$(filter -l%,$(LIBS)))
# the path to the libraries (with `lib' prefix added)
_LIB_PATHS     := $(addprefix ../../libraries/lib,$(_ALL_LIBNAMES))
# all library directories that already exist
_EXISTING_DIRS := $(wildcard ../../libraries/*)
# the intersection of _LIB_PATHS and _EXISTING_DIRS, e.g. the paths to
# the libraries that exist, and are used
USED_LIB_DIRS   = $(filter $(_EXISTING_DIRS),$(_LIB_PATHS))

# debugging
# $(info Included libraries: $(_LIB_PATHS))
# $(info Existing directories: $(_EXISTING_DIRS))
# $(info Dirs to rebuild: $(USED_LIB_DIRS))

####### TARGETS ########
all: $(BIN)

# static pattern rule
# https://www.gnu.org/software/make/manual/make.html#Static-Pattern
.PHONY: $(USED_LIB_DIRS)
$(USED_LIB_DIRS): % :
	$(info Ensuring $@ is up to date)
	@make -C $@

clean:
	$(RM) $(OBJS) $(BIN) $(LSTS) $(PRJ).bin $(PRJ).l68 $(PRJ).map

# Open source in default editor, on mac.
open:
	-edit $(SRC_C) $(SRC_S) Makefile

run:	$(BIN)
ifeq ($(CODE_LOC),rom)
	@echo ERROR: Can only upload a RAM project!
else
	../../../uploader/uploader $(PRJ).bin
endif

upload: $(BIN)
	../../../srec2srb/srec2srb $(BIN) /tmp/_$(PRJ).srb
	../../../uploader/uploader -x -b -s $(ULFLAGS) /tmp/_$(PRJ).srb

listing: $(LSTS)

$(BIN): $(USED_LIB_DIRS) $(wildcard ../../lib/*.a) $(OBJS)
	$(LD) $(OBJS) $(LIBPATHS) $(LIBS) $(LDFLAGS) -o $(BIN) -Map $(PRJ).map
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
