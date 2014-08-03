#ifndef __UPLOADER_H__
#define __UPLOADER_H__

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdarg.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <sys/poll.h>
#include <ctype.h>
#include <sys/time.h>
#include <string.h>
#include <unistd.h>
#include "srec_parse_uploader.h"

#include "../projects/include/loader.h"

typedef uint8_t bool;
#define true 1
#define false 0

// general functions
uint64_t millis();

// s-rec info variables
extern uint32_t program_sz;
extern uint32_t entry_point;
extern uint8_t erased_sectors[SECTOR_COUNT];

// RTS pin to assert/deassert on commands
extern const int pin_rts;
extern bool can_timeout;

#define msleep(x) usleep((x) * 1000)

/* __UPLOADER_H__ */
#endif
