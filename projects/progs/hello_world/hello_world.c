#include "stdlib.h"
#include "io.h"

void main() {
    while(true) {
        TIL311 = 0x11;
        DELAY_MS(1000);
        TIL311 = 0x22;
        DELAY_MS(1000);
    }
}
