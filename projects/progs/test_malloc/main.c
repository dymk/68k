#include "stdlib.h"
#include "serial.h"
#include "malloc.h"

int main() {
    serial_start(SERIAL_SAFE);

    void *thing = malloc(10);
    void *thing2 = malloc(10);

    strcpy(thing, "hi!\n");

    puts("say hi: ");
    puts(thing);

    return 0;
}
