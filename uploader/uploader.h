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

// serial functions
static uint8_t readb(int serial_fd);
static uint16_t readw(int serial_fd);
static uint32_t readl(int serial_fd);

static void putl(int serial_fd, uint32_t i);
static void putwd(int serial_fd, uint32_t i);

static int sergetc(int serial_fd);
static int serputc(int serial_fd, char c);
static void serflush(int serial_fd);
static uint8_t has_data(int serial_fd);

// send command to the bootloader
static void command(int serial_fd, uint8_t instr);

static int set_address(int serial_fd, uint32_t addr);

// execute a flag set command
static bool SET_FLAG(int serial_fd, const char * name, uint8_t value, uint32_t magic) ;

// large functions
static int perform_dump(int serial_fd, const char *file, uint32_t addr, uint32_t len);
static void monitor(int serial_fd);

// general functions
static uint64_t millis();
static uint32_t crc_update (uint32_t inp, uint8_t v);
static void hex_dump(uint8_t *array, uint32_t cnt, uint32_t baseaddr) ;

/* __UPLOADER_H__ */
#endif
