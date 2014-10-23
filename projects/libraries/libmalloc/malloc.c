#include "malloc.h"

extern uint32_t *__heap_start;
static uint32_t *head = 0;

void *malloc(size_t size) {
    if(head == 0) {
        head = __heap_start;
    }

    // round `size' up to the nearest multiple of 4
    size = size + (4 - (size % 4));

    uint32_t ret = head;
    head += size;
    return ret;
}
