#ifndef __SERIAL_IO_H__
#define __SERIAL_IO_H__

#include "uploader.h"

// serial functions
uint8_t readb(int serial_fd);
uint16_t readw(int serial_fd);
uint32_t readl(int serial_fd);

void putl(int serial_fd, uint32_t i);
void putwd(int serial_fd, uint32_t i);

int sergetc(int serial_fd);
int serputc(int serial_fd, char c);
void serflush(int serial_fd);
uint8_t has_data(int serial_fd);

// send command to the bootloader
void command(int serial_fd, uint8_t instr);

int set_address(int serial_fd, uint32_t addr);

// __SERIAL_IO_H__
#endif
