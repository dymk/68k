#include "uploader.h"
#include "serial_io.h"

#define IOSSDATALAT    _IOW('T', 0, unsigned long)
#define IOSSIOSPEED    _IOW('T', 2, speed_t)

#define ROL(num, bits) (((num) << (bits)) | ((num) >> (32 - (bits))))


// execute a flag set command
static bool SET_FLAG(int serial_fd, const char * name, uint8_t value, uint32_t magic) ;

// large functions
static int perform_dump(int serial_fd, const char *file, uint32_t addr, uint32_t len);
static void monitor(int serial_fd);

static uint32_t crc_update (uint32_t inp, uint8_t v);
static void hex_dump(uint8_t *array, uint32_t cnt, uint32_t baseaddr) ;

// default port
const char port_def[] ="/dev/cu.usbserial-FTWEIJYD";

const int pin_rts = TIOCM_RTS;

// simulated system memory
uint8_t MEMORY[0x100000];

// file descriptor... getting lazy...
bool can_timeout = true;

void usage() {
    printf(
        "\nUsage: upload-loader [options] file\n"
        "\n"
        "-t             only act as terminal emulator\n"
        "-n             do not enter terminal emulator mode after load\n"
        "-v             verbose verification error log\n"
        "-s             file to load is a motorola s-record\n"
        "-f             allow s-record to write flash\n"
        "-l             allow s-record to write loader (must also specify -f)\n"
        "-x             boot from entry point specified in s-record\n"
        "-b             s-record is in binary format from srec2srb\n"
        "-c             enable qcrc validation (implicit in -s)\n"
        "-p port        specify serial port (full path to device)\n"
        "-d addr[:len]  dump specified region of memory, in hex or dec.\n"
        "\n"
    );
}

uint32_t parse_num(const char *c) {
    uint32_t ret;

    if (c[0] == '$') {
        c++;
        if (!sscanf(c," %x",&ret)) {
            printf("Argument error parsing %s\n", c);
            exit(1);
        }
        return ret;
    }

    if (c[0] == '0' && c[1] == 'x') {
        c+=2;
        if (!sscanf(c," %x",&ret)) {
            printf("Argument error parsing %s\n", c);
            exit(1);
        }
        return ret;
    }

    if (!sscanf(c," %u",&ret)) {
            printf("Argument error parsing %s\n", c);
            exit(1);
    }
    return ret;
}


typedef struct RunFlags_ {
    // don't enter terminal mode afterwards
    bool no_terminal;

    // verbose debug output
    bool verbose;

    // only enter terminal mode (no uploading)
    bool term_only;

    // quick CRC check
    bool use_qcrc;

    // dump 68k memory to disk
    bool do_dump;

    // address/length to dump
    char *dump_arg;

    // boot from entrypoint specified in srec
    bool boot_srec;

    // allow srec to write to flash
    bool flash_wr;

    // allow srec to write to loader
    bool loader_wr;

    // file to load is a binary srec
    bool bin_srec;

    // file to load is a motorola srec
    bool is_srec;

    // internal use
    bool set_addr;

    // file to dump to or upload from
    const char *filename;
} RunFlags;

int main (const int argc, char **argv) {
    if (argc == 1) {
        usage();
        return 1;
    }

    // serial port to do comms over (default to port_def)
    const char *port = port_def;

    // program flags
    RunFlags flags;
    memset(&flags, 0, sizeof(flags));


    // should allow setting of this
    int BAUD_RATE = 28000;

    // default address and length to dump
    uint32_t addr = 0;
    uint32_t len = 256;

    int c;
    while((c = getopt(argc, argv, "htnvsflxbcp:d:")) != -1) {
        switch(c) {
        case 'h': usage(); return 1;
        case 't': flags.term_only   = true; break;
        case 'n': flags.no_terminal = true; break;
        case 'v': flags.verbose     = true; break;
        case 's': flags.is_srec     = true; break;
        case 'l': flags.loader_wr   = true; break;
        case 'f': flags.flash_wr    = true; break;
        case 'x': flags.boot_srec   = true; break;
        case 'b': flags.bin_srec    = true; break;
        case 'c': flags.use_qcrc    = true; break;
        case 'p': port = optarg; break;
        case 'd':
            flags.do_dump = true;
            flags.dump_arg = optarg;
            break;

        case '?':
            if(c == 'p' || c == 'd') {
                fprintf(stderr, "Option '-%c' requires an argument\n", c);
            }
            else {
                fprintf(stderr, "Unknown option '-%c'\n", c);
            }
            return EXIT_FAILURE;

        default:
            fprintf(stderr, "Internal error, got unhandled option: '-%c'\n", c);
            return EXIT_FAILURE;
        }
    }

    if (flags.do_dump) {
        char *dump_arg = flags.dump_arg;
        char *addr_s   = dump_arg;
        char *len_s    = NULL;

        for (int i = 0; i < 100; i++) {
            char ch = dump_arg[i];
            if (
                !(ch >= '0' && ch <= '9') &&
                !(ch >= 'a' && ch <= 'f') &&
                !(ch >= 'A' && ch <= 'F') &&
                ch != 'x' &&
                ch != '$')
            {
                if (ch == 0)
                    break;

                len_s = addr_s + i + 1;
                dump_arg[i] = '\0';
            }
        }

        addr = -1;
        addr = parse_num(addr_s);

        if (len_s) {
            len = parse_num(len_s);
        }


        if (len == 0 || len > 768 * 1024) {
            printf("Bad length argument: value of %d is invalid.\n",len);
            return 1;
        }

        if (addr == -1 || addr > 768 * 1024) {
            printf("Bad address argument: value of %d is invalid.\n",addr);
            return 1;
        }
    }

    // passed a filename as well
    if(optind < argc) {
        flags.filename = argv[optind];
    }

    printf("Open port %s ... ", port);
    int serial_port = open(port, O_RDWR);

    if (serial_port <= 0) {
        printf("FAILED!\n");
        return 1;
    }

    printf("OK\n");

    // remove any pending characters
    serflush(serial_port);

    unsigned long mics = 1UL; // set latency to 1 microsecond
    ioctl(serial_port, IOSSDATALAT, &mics);

    speed_t speed = BAUD_RATE; // Set baud

    // since the FTDI driver is shit, hard rate the data rate
    // to the max possible by baud rate (in chunks of 512)
    int BAUD_DELAY = (int)(1000.0F / (BAUD_RATE / 9) * 512);

    ioctl(serial_port, IOSSIOSPEED, &speed);
    ioctl(serial_port, TIOCMBIC, &pin_rts); // deassert RTS

    if (flags.term_only) {
        monitor(serial_port);
        return 0;
    }

    if (flags.do_dump) {
        return perform_dump(serial_port, flags.filename, addr, len);
    }

    if (flags.filename == NULL) {
        fprintf(stderr, "Missing filename.\n");
        return 1;
    }

    FILE *in = fopen(flags.filename, "rb");

    if (!in) {
        fprintf(stderr, "Failed to open: %s\n", flags.filename);
        return 1;
    }

    // get file size
    long size = 0;
    if(fseek (in, 0, SEEK_END) == 0) {
        size = ftell(in);
    }
    else {
        perror("fseek");
        return 1;
    }
    rewind(in);

    printf("File size: %ld\n", size);

    // allocate buffers
    uint8_t *data     = (uint8_t*)malloc(size+1);
    uint8_t *readback = (uint8_t*)malloc(size+1);

    if (!data || !readback) {
        fprintf(stderr, "Failed to allocate memory\n");
        return 1;
    }

    if (fread(data, 1, size, in) != size) {
        fprintf(stderr, "Did not read entire file\n");
        return 1;
    }

    fclose(in);

    // set flags as relevant
    uint8_t srec_flags =
        (flags.flash_wr  ? ALLOW_FLASH  : 0) |
        (flags.loader_wr ? ALLOW_LOADER : 0) |
        (flags.bin_srec  ? BINARY_SREC  : 0);

    // clear simulated memory
    memset(MEMORY, 0, sizeof(MEMORY));

    if (flags.is_srec) {
        // add trailing null
        data[size++] = 0;

        printf("Validating S-record... ");
        uint8_t ret = parseSREC(data, size+1, srec_flags, true);

        if (ret) {
            fprintf(stderr, "\nFailed to validate S-record. Ret: ");
            for (int i = 7; i >= 0; i--) {
                fprintf(stderr, "%c", ((ret >> i) & 0x1) + '0');

                if(i == 4) {
                    fprintf(stderr, " ");
                }
            }

            printf("\n");

            if (ret & BAD_HEX_CHAR || ret & FORMAT_ERROR) {
                fprintf(stderr, "\nVerify that the file is not corrupt.\n");
            }

            fprintf(stderr, "\nProgramming aborted.\n");
            return 1;
        }
        else {
            printf("OK.\n");
        }

        if (flags.boot_srec) {
            if(entry_point == 0) {
                printf("Error: -b flag present, but S-record does not specify an entry point. Aborting!\n");
                return 1;
            }
            else {
                printf("Entry point of 0x%X\n",entry_point);
            }
        }

        printf("Payload size: %d\n",program_sz);
        flags.use_qcrc = true;
        flags.set_addr = true;

        // a loader write will be executed: do a sanity check
        if (flags.loader_wr && erased_sectors[0]) {
            printf("\n*** Loader sector WILL be cleared. ***\n");

            uint32_t
                sp = 0,
                pc = 0,
                a = 0x80000;

            // read stack pointer from simulated memory, big endian
            sp |= MEMORY[a++];
            sp <<= 8;
            sp |= MEMORY[a++];
            sp <<= 8;
            sp |= MEMORY[a++];
            sp <<= 8;
            sp |= MEMORY[a++];

            // read program counter from simulated memory, big endian
            pc |= MEMORY[a++];
            pc <<= 8;
            pc |= MEMORY[a++];
            pc <<= 8;
            pc |= MEMORY[a++];
            pc <<= 8;
            pc |= MEMORY[a++];

            printf("SP: 0x%06X  PC: 0x%06X\n", sp, pc);

            if (sp > FLASH_START) {
                printf("\nERROR: SP is not located in RAM. Aborting!\n");
                return 1;
            }

            if (pc < FLASH_START || pc >= IO_START) {
                printf("\nERROR: PC is not located in FLASH. Aborting!\n");
                return 1;
            }

            if (!erased_sectors[ADDR_TO_SECTOR(pc)]) {
                printf("\nERROR: PC is located in a sector that was not written to. Aborting!\n");
                return 1;
            }

            if (ADDR_TO_SECTOR(pc) != 0)
                printf("\nWarning: PC is not located in the bootloader sector - it is in sector %d.\n", ADDR_TO_SECTOR(pc));

            const char *conf_chars = " !@#$%^&*()";
            srand(time(NULL));

            if (flags.loader_wr && flags.flash_wr) {
                int num = (rand() % 9) + 1;

                printf("\n");
                printf("#####################################################################\n");
                printf("# WARNING: Loader write and Flash write have both been enabled.     #\n");
                printf("# At least one write to the bootloader sector will be executed.     #\n");
                printf("# The stack pointer and program counter values appear to be sane.   #\n");
                printf("#                                                                   #\n");
                printf("# Please confirm that you want to update the bootloader sector      #\n");
                printf("# by pressing SHIFT+'%d', then enter. Press any other key to abort. #\n", num);
                printf("#####################################################################\n\n ");
                printf("> ");

                if (getchar() != conf_chars[num]) {
                    fprintf(stderr, "\nAborting!\n");
                    return 1;
                }

                printf("\nContinuing with programming.\n");
            }
        }
    }

    ////////////////////////////////

    printf("Sending reboot command...\n");

    bool programmed_ok = false;

    while (!programmed_ok) {
        programmed_ok = true;

        // reset board
        command(serial_port, CMD_RESET);
        msleep(200);
        serflush(serial_port);

        if (flags.set_addr) {
            // aligned load address with just enough room to load entire file without clobbering stack
            uint32_t load_addr = (0x80000 - 4096 - size) & ~1;

            if (!set_address(serial_port, load_addr)) {
                return 1;
            }
        }

        printf("Uploading...\n");

        char ch;
        int rbi = 0;
        int i;
        int wrSz = 16;

        int expct_crc = 0xDEADC0DE;
        for (i = 0; i < size; i ++)
            expct_crc = crc_update(expct_crc,data[i]);

        for (i = 0; i < size; i += wrSz) {
           // serputc(fd, data[i]);
           if ((size-i) < 16){
          	    wrSz = (size-i);
          	   // printf("final write of %d bytes",wrSz);
            }

            if (write(serial_port, &data[i], wrSz) != wrSz) {
        		fprintf(stderr, "Serial write failed!");
       			return 1;
   			}

            if (i % 512 == 0) {
                printf("%3ld %%\x8\x8\x8\x8\x8",(int)((float)i * 100) / size);
                fflush(stdout);
                msleep(BAUD_DELAY);
                // sleep because the ftdi driver is terrible, so we hard rate limit
            }

			while (has_data(serial_port))
				if (read(serial_port, &ch, 1) == 1) {
					readback[rbi++] = ch;
				}
                else {
					fprintf(stderr, "Serial read error.\n");
					return 1;
				}

        }

        // done!
        printf("%3d %%\n\n",100);

        uint64_t start = millis();

        // read additional bytes while they are available, wait up to 250ms for data
        while(true) {
            if (has_data(serial_port)) {
            	if(read(serial_port, &ch, 1) == 1) {
					readback[rbi] = ch;
					start = millis();
					rbi++;
            	}
                else {
                	printf("Serial read error.\n");
                	return 1;
                }
            }

            if ((millis() - start) > 250 || (rbi > size*2)) {
            	break;
            }
        }

        if (size/10 > rbi) {
            printf("Only %d bytes read. Reset board manually and try again.\n\n", rbi);
            close(serial_port);
            return 1;
        }

        // validate CRC, if enabled
        if (flags.use_qcrc) {
            command(serial_port, CMD_QCRC);

            uint16_t intro = readw(serial_port);
            uint32_t crc   = readl(serial_port);
            uint8_t nul    = readb(serial_port);

            if (intro != 0xFCAC || nul != 0) {
                fprintf(stderr, "Sync error reading CRC. Reset board and try again.\n");
                fprintf(stderr, "Error: %s\n\n", (nul != 0) ? "Intro invalid." : "Tail invalid.");
                return 1;
            }

            if (crc != expct_crc) {
                printf("CRC ERROR: Got %08X, expected %08X\n",crc,expct_crc);
                printf("Retrying.\n\n");
                continue;
            } else
                printf("CRC verified: 0x%08X\n", crc);
        }

        // validate readback
        int errors = 0;

        for (int i = 0; i < size; i++) {
            if (data[i] != readback[i]) {
                if (errors == 0 || flags.verbose) {
                    printf("Mismatch at byte %d: expected %d, got %d\n",i, data[i],readback[i]);
                    programmed_ok = false;
                }
                errors++;
            }
        }

        // okay, errors? otherwise boot.
        if (errors) {
            printf("Verification FAILED with %d errors. Retrying.\n\n",errors);
        } else {
            printf("Upload echo verified.\n\n");

            if (flags.is_srec) {
                // apply relevant flags

                if (flags.flash_wr  && !SET_FLAG(serial_port, "flash write", CMD_SET_FLWR, FLWR_MAGIC)) {
                    return 1;
                }

                if (flags.loader_wr && !SET_FLAG(serial_port, "loader write", CMD_SET_LDWR, LDWR_MAGIC)) {
                    return 1;
                }

                if (flags.bin_srec  && !SET_FLAG(serial_port, "binary srec", CMD_SET_BINSR, BINSREC_MAGIC)) {
                    return 1;
                }

                printf("Programming SREC");
                fflush(stdout);

                // execute command
                command(serial_port, CMD_SREC);

                uint32_t ok = readl(serial_port);

                if (ok != SREC_GREET_MAGIC) {
                    printf("\nSync error writing srec (bad greeting). Reset board and try again.\nGot %08X, expected %08X\n\n", ok, 0xD0E881CC);
                    return 1;
                } else {
                    printf(" in progress...\n");
                    fflush(stdout);
                }

                // uint64_t started = millis();
                // uint8_t wr_flags = readb();

                // this can take a while, so disable serial timeouts
                // only relevant for older bootloader versions
                can_timeout = false;

                uint8_t ch;

                // echo progress
                while ((ch = readb(serial_port)) != 0xC0) {
                    printf("%3hhX %%\x8\x8\x8\x8\x8",ch);
                    fflush(stdout);
                }

                printf("100 %%\n\n");

                // read the lower byte of what hopefully is 0xC0DE
                uint32_t c0de = (((uint16_t)ch)<< 8) | readb(serial_port);

                can_timeout = true;

                uint64_t end = millis();

                if (c0de != SREC_CODE_MAGIC) {
                    printf("Sync error writing srec (bad c0de). Reset board and try again.\nGot %04X, expected %04X\n\n", c0de, SREC_CODE_MAGIC);
                    return 1;
                }

                uint16_t ret_code = readw(serial_port);
                uint16_t tail_magic = readw(serial_port);

                if (tail_magic != SREC_TAIL_MAGIC) {
                    printf("Sync error writing srec (bad tail). Reset board and try again.\nGot %04X, expected %04X\n\n", tail_magic, SREC_TAIL_MAGIC);
                    return 1;
                }

                if (ret_code) {
                    printf("Failed. Error %hx: ", ret_code);
                    for (int i = 7; i >= 0; i--) {
                        printf ("%c",((ret_code >> i) & 0x1) + '0');
                        if (i == 4) printf(" ");
                    }

                    printf("\n\n");
                    return 1;
                }

                printf("Write completed successfully in %llu ms.\n\n", end - start);

                if (!flags.boot_srec) {
                    flags.no_terminal = true;
                } else {
                    set_address(serial_port, entry_point);
                    printf("Booting program.\n\n");
                    command(serial_port, CMD_BOOT);
                }

                break;
            } else {
                printf("Booting program.\n\n");
                command(serial_port, CMD_BOOT);
                break;
            }
        }
    }

    if (!flags.no_terminal)
        monitor(serial_port);

    close(serial_port);

    return 0;
}

int perform_dump(int serial_fd, const char *file, uint32_t addr, uint32_t len) {
    FILE *out = fopen(file,"w");

    if (
        (file && out == NULL) ||
        (!file && len >= 5000))
    {
        printf("Failed to open '%s' for memory dump.\n",file);
    }

    printf("Performing dump of %d bytes starting at 0x%06X\n",len, addr);
    printf("Resetting board...\n");
    command(serial_fd, CMD_RESET);
    serflush(serial_fd);

    if (!set_address(serial_fd, addr))
        return 1;

    printf("Sending dump command... \n");
    command(serial_fd, CMD_DUMP);

    uint32_t greeting = readw(serial_fd);

    if (greeting != DUMP_GREET_MAGIC) {
        printf("Sync error in greeting. Got 0x%x\n", greeting);
        return 1;
    }

    putl(serial_fd, len);

    uint32_t addr_rb, len_rb;
    addr_rb = readl(serial_fd);
    len_rb = readl(serial_fd);

    if (addr_rb != addr || len_rb != len) {
        putl(serial_fd, 0);
        printf("Bad readback of length/address! Dump aborted...\n");
        printf("Address: read 0x%06X, expected 0x%06X\n", addr_rb, addr);
        printf("Length:  read 0x%06X, expected 0x%06X\n", len_rb, len);
        return 1;
    }

    putwd(serial_fd, DUMP_START_MAGIC);

    int crc = 0xDEADC0DE;
    char ch;

    uint64_t start = millis();
    uint64_t lastByte = start;
    uint32_t sz = 0;

    uint8_t *dump = (uint8_t*)malloc(len);
    if (!dump) {
        printf("Failed to allocate memory\n");
        return 1;
    }

    printf("\n");

    while (sz < len) {
        if (has_data(serial_fd)) {
            if(read(serial_fd, &ch, 1) == 1) {

                if (out) fputc(ch, out);

                crc = crc_update(crc, ch);

                lastByte = millis();
                dump[sz++] = ch;

                if (sz % 32 == 0) {
                    printf("%6.2f %%\x8\x8\x8\x8\x8\x8\x8\x8",((float)sz * 100) / len);
                    fflush(stdout);
                }
            } else {
                printf("Serial read error.\n");
                return 1;
            }
        } else usleep(10);

        if ((millis() - lastByte) > 250) {
            printf("Error: timeout in dump (no data for 250ms)\n");
            return 1;
        }
    }

    uint64_t end = millis();

    printf("%6.2f %%\n\n",((float)100));

    uint32_t rem_crc = readl(serial_fd);
    uint16_t tail = readw(serial_fd);

    if (tail != DUMP_TAIL_MAGIC) {
        printf("Sync error in tail. Got 0x%x\n", tail);
        return 1;
    }

    printf("Read %d bytes in %llu ms\n", sz, end - start);
    // (%3.2f bytes/s) ((float)sz) / (((float)(end-start))/ 1000)

    if (crc != rem_crc) {
        printf("ERROR: CRC MISSMATCH!\n");
        printf("Local CRC:  0x%08X\n",crc);
        printf("Remote CRC: 0x%08X\n",rem_crc);
        return 1;
    }

    printf("CRC validated as 0x%08X\n",crc);
    printf("Dump completed successfully.\n");

    if (len < 5000)
        hex_dump(dump, len, addr);

    if (out) fclose(out);
    return 0;
}

static void hex_dump(uint8_t *array, uint32_t cnt, uint32_t baseaddr) {
    int c = 0;
    char ascii[17];
    ascii[16] = 0;

    printf("\n%8X   ", baseaddr);

    for (uint32_t i = 0; i < cnt; i++) {
        uint8_t b = array[i];

        ascii[c] = (b > 31 & b < 127) ? b : '.';

        printf("%02X ",b);

        if (++c == 16) {
            printf("  %s\n",ascii);
            if ((i+1) < cnt)
                printf("%8X   ", baseaddr+i+1);
            c = 0;
        }
    }

    if (c && c < 15) {
        ascii[c] = 0;
        while (c++ < 16)
            printf("   ");
        printf("  %s\n",ascii);
    }
    else {
        printf("\n");
    }
}

// perform a flag-set command (returns a magic value)
bool SET_FLAG(int serial_fd, const char * name, uint8_t value, uint32_t magic) {
    printf("Setting %s... ",name);
    fflush(stdout);

    command(serial_fd, value);
    uint32_t ok = readl(serial_fd);

    if (ok != magic) {
        printf("Sync error setting %s. Reset board and try again.\nGot %08X, expected %08X\n\n", name, ok, magic);
        return 0;
    }

    printf("OK.\n");
    return 1;
}

void monitor(int serial_fd) {
    // ensure nodelay is on
    int flags = fcntl(serial_fd, F_GETFL);
    flags |= O_NDELAY;
    fcntl(serial_fd,F_SETFL,flags);

    // turn off line buffering and local echo
    struct termios oldt;
    tcgetattr( STDIN_FILENO, &oldt );
    oldt.c_lflag &= ~(ICANON | ECHO);
    tcsetattr( STDIN_FILENO, TCSANOW, &oldt );

    printf("###### Serial Terminal ##########################################\n");

    char ch;
    while (true) {
        if (has_data(0))
            serputc(serial_fd,getchar());

        while (1 == read(serial_fd, &ch, 1)) {
            if (isprint(ch) || ch == '\n') {
                putchar(ch);
            } else {
               // printf("ʘ");
               printf ("[ʘx%02X]", ch&0xFF);
               // fprintf(stderr, "%d\n",ch);
            }
        }

        fflush(stdout);
        msleep(10);
    }
}

uint32_t crc_update (uint32_t inp, uint8_t v) {
	return ROL(inp ^ v, 1);
}

uint64_t millis() {
    struct timeval tv;

    gettimeofday(&tv, NULL);

    return (tv.tv_sec * 1000 + tv.tv_usec / 1000);
}
