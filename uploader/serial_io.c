#include "serial_io.h"

uint8_t readb(int serial_fd) {
    return sergetc(serial_fd);
}

uint16_t readw(int serial_fd) {
    return (((uint16_t)readb(serial_fd)) << 8) | readb(serial_fd);
}

uint32_t readl(int serial_fd) {
    return (((uint32_t)readw(serial_fd)) << 16) | readw(serial_fd);
}

void putl(int serial_fd, uint32_t i) {
    serputc(serial_fd, (i >> 24) & 0xFF);
    serputc(serial_fd, (i >> 16) & 0xFF);
    serputc(serial_fd, (i >>  8) & 0xFF);
    serputc(serial_fd, (i      ) & 0xFF);
}

void putwd(int serial_fd, uint32_t i) {
    serputc(serial_fd, (i >>  8) & 0xFF);
    serputc(serial_fd, (i      ) & 0xFF);
}

int serputc(int serial_fd, char c) {
    // printf("xmit %02hhx\n",c);
    if (write(serial_fd, &c, 1) != 1) {
        printf("Serial write failed");
        exit(1);
    }
    return 1;
}

// empty the entire input queue
// so we should be in sync
void serflush(int serial_fd) {
    char ch;
    msleep(100);
    while (has_data(serial_fd))
        read(serial_fd, &ch, 1);
}

int sergetc(int serial_fd) {
    uint64_t start = millis();
    uint64_t t;

    while(!has_data(serial_fd)) {
        t = millis();
        if (can_timeout && (t-start) > 2000) {
            printf("Timeout occurred in sergetc(). Ensure bootloader supports command.\n");
            exit(1);
        }
        usleep(10);
    }

    char ch;
    int ret = read(serial_fd, &ch, 1);
    if (ret == -1) {
        printf("\n *** Serial read failed %d ***\n",ret);
        exit(1);
    }

   // printf("rec  %02hhx\n",ch);
    return ch;
}

void serprintf(int fd, const char *fmt, ... ){
    char buf[256];
    va_list args;
    va_start (args, fmt );
    int l = vsnprintf(buf, 256, fmt, args);
    va_end (args);

    if (write(fd, &buf,l) != l) {
        printf("Failed to write entire buffer\n");
        exit (1);
    }
}

uint8_t has_data(int serial_fd) {
    struct pollfd poll_str;
    poll_str.fd = serial_fd;
    poll_str.events = POLLIN;

    return poll(&poll_str, 1, 0);
}

void command(int fd, uint8_t instr) {
    ioctl(fd, TIOCMBIS, &pin_rts); // assert RTS
    usleep(50*1000);

    if (instr == CMD_RESET) { // send multiple to ensure we enter bootloader mode
        for (int i = 0; i < 8; i++) {
            serputc(fd, instr);
            usleep(25*1000);
        }
    } else {
        serputc(fd, instr);
        usleep(50*1000);
    }

    ioctl(fd, TIOCMBIC, &pin_rts); // deassert RTS
}

int set_address(int serial_fd, uint32_t addr) {
    printf("Setting address to 0x%x... ", addr);
    fflush(stdout);

    command(serial_fd, CMD_SET_ADDR);

    uint32_t intro = readl(serial_fd);

    if (intro != ADDR_MAGIC) {
        printf("Sync error setting write address: got %x\n", intro);
        return 0;
    }

    putl(serial_fd, addr);
    uint32_t addr_rb = readl(serial_fd);
    uint16_t tail = readw(serial_fd);

    if (tail != ADDR_TAIL_MAGIC) {
        printf("Sync error in SetAddr tail: got %x\n", tail);
        return 0;
    }

    if (addr_rb != addr) {
        printf("Address verification failed (got %x, expected %x)\n", addr_rb, addr);
        return 0;
    }

    printf("OK!\n");

    return 1;
}
