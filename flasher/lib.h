#ifndef __LIB_H__
#define __LIB_H__

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <Arduino.h>
#include <HardwareSerial.h>

// portions from https://github.com/ZigZagJoe/68k

void _printf(char *fmt, ... ){
	char buf[128]; // resulting string limited to 128 chars
	va_list args;
	va_start (args, fmt );
	vsnprintf(buf, 128, fmt, args);
	va_end (args);
	Serial.print(buf);
}

typedef enum {
	READY = 'a',  // 'a' Chip ready
	SUCCESS,      // 'b' Generic success
	FAIL,         // 'c' Generic failure
	PONG,         // 'd' Pong response
	UNKNOWN       // 'e' Unknown request (implies failure)
} Response;

typedef enum {
	ERASE = 'A', // 'A' Erase the flash chip
	PING,        // 'B' recieved ping request

	SET_ADDR,    // 'C' Set address bus to next two bytes recieved
	SET_DATA,    // 'D' Set data bus to next byte recieved
} Request;

#endif /* __LIB_H__ */
