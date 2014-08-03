#ifndef __LOADER_H__
#define __LOADER_H__

#include "stdint.h"
#include "stdlib.h"
#include "io.h"
#include "binary.h"

// Default address to place recieved binaries
#define DEFAULT_ADDRESS ((uint8_t*)0x2000)

// Uploader commands
typedef enum {
    CMD_SET_FLWR  = 0xC1,
    CMD_SET_LDWR  = 0xC2,
    CMD_SET_BINSR = 0xC3,
    // unused 0xC4-C9
    CMD_DUMP      = 0xCA,
    CMD_BOOT      = 0xCB,
    CMD_QCRC      = 0xCC,
    CMD_SREC      = 0xCD,
    CMD_SET_ADDR  = 0xCE,
    CMD_RESET     = 0xCF
} COMMAND;

typedef enum {
    LF_WRITE_FLASH = 1,
    LF_WRITE_LOADER = 2,
    LF_IS_BINSREC = 4
} LOADER_FLAGS;

// entrypoint for the relocated bootloader
void loader_start();

// execute a command sent by the uploader
void command(COMMAND cmd) __attribute__((always_inline));

// get a charachter from USART
uint8_t getc() __attribute__((always_inline));
void putc(uint8_t byte) __attribute__((always_inline));

/* __LOADER_H__ */
#endif
