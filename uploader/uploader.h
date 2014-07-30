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

#include "../projects/include/loader.h"

typedef uint8_t bool;
#define true 1
#define false 0

// serial functions
static uint8_t readb();
static uint16_t readw();
static uint32_t readl();

static void putl(uint32_t i);
static void putwd(uint32_t i);

static int sergetc(int fd);
static int serputc(int fd, char c);
static void serflush(int fd);
static uint8_t has_data(int fd);

// send command to the bootloader
static void command(int fd, uint8_t instr);

static int set_address(uint32_t addr);

// execute a flag set command
static bool SET_FLAG(const char * name, uint8_t value, uint32_t magic) ;

// large functions
static int perform_dump(uint32_t addr, uint32_t len);
static void monitor(int fd);

// general functions
static uint64_t millis();
static uint32_t crc_update (uint32_t inp, uint8_t v);
static void hex_dump(uint8_t *array, uint32_t cnt, uint32_t baseaddr) ;

/* __UPLOADER_H__ */
#endif
