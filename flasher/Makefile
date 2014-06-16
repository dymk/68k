ARDUINO_DIR = /g/Programs/arduino-1.0.5
AVR_DIR     = /g/Programs/WinAVR-20100110
CXX := $(AVR_DIR)/bin/avr-g++

F_CPU 	= 16000000L
MCU     = atmega328p

# Headers included by the Arduino platform
ARDUINO_INC_DIR1 = /g/Programs/arduino-1.0.5/hardware/arduino/cores/arduino
ARDUINO_INC_DIR2 = /g/Programs/arduino-1.0.5/hardware/arduino/variants/standard
AVR_INC_DIR = /g/Programs/arduino-1.0.5/hardware/tools/avr/avr/include

# Directory with arduino library files (all the .cpp ones)
ARDUINO_LIB_DIR = /g/Programs/arduino-1.0.5/hardware/arduino/cores/arduino

# Generic headers supplied to avr-gcc
CXX_INC_FLAGS = -I$(ARDUINO_INC_DIR1) -I$(ARDUINO_INC_DIR2) -I$(AVR_INC_DIR)
CXX_FLAGS     = -mmcu=$(MCU) -DF_CPU=$(F_CPU) $(CXX_INC_FLAGS)

all: flasher.cpp arduino.o
	$(CXX) flasher.cpp arduino.o -o flasher $(CXX_FLAGS)

# Compiled arduino libs
arduino.o:
	$(CXX) -o arduino.o $(ARDUINO_LIB_DIR)/HardwareSerial.cpp $(ARDUINO_LIB_DIR)/wiring_digital.c $(ARDUINO_LIB_DIR)/Print.cpp -c $(CXX_FLAGS)

clean:
	rm -f arduino.o
	rm -f flasher
