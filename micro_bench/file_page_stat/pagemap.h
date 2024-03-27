#ifndef PAGEMAP_H
#define PAGEMAP_H

#include <stdint.h>

#define PAGEMAP_ENTRY 8

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  uint64_t pfn : 54;
  unsigned int soft_dirty : 1;
  unsigned int file_page : 1;
  unsigned int swapped : 1;
  unsigned int present : 1;
} pagemap_entry_t;

int is_bigendian();
int read_pagemap(int fd, unsigned long virt_addr, pagemap_entry_t *entry);
#ifdef __cplusplus
}
#endif

#endif
