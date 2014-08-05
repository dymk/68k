# 68008 lib makefile

####### VARIABLES #######

# Get directory name, to use as output filename.
PRJ = $(notdir $(CURDIR))
LIB = ../../lib/$(PRJ).a

# Program names

RM   = rm -f
CC   = m68k-elf-gcc
AR   = m68k-elf-ar
AS   = m68k-elf-as

SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
include $(SELF_DIR)/common.mk

ARFLAGS = -ar rcs $(LIB)

# clear suffixes
.SUFFIXES:
.SUFFIXES: .c .o .lst .s

####### TARGETS ########

all:	$(LIB)

clean:
	$(RM) $(OBJS) $(LSTS) $(LIB)

backup:
	cd ..; backup $(PRJ)

# Open source in default editor, on mac.
open:
	-open $(SRCS)

listing: $(LSTS)

$(LIB): $(OBJS)
	$(AR) $(ARFLAGS) $(OBJS)

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

.c.lst:
	$(CC) $(CFLAGS) -c -S -o $@ $<

.s.o:
	$(AS) $(ASFLAGS) -o $@ $<
