#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "pagemap.h"

inline int is_bigendian() {
  static const int __endian_bit = 1;
  return (*(char *)&__endian_bit) == 0;
}
int read_pagemap(int fd, unsigned long virt_addr, pagemap_entry_t *entry) {
  int i, status;
  char c;
  uint64_t file_offset, data;
  // Shifting by virt-addr-offset number of bytes
  // and multiplying by the size of an address (the size of an entry in pagemap
  // file)
  file_offset = virt_addr / getpagesize() * PAGEMAP_ENTRY;
  status = lseek(fd, file_offset, SEEK_SET);
  if (status == -1) {
    printf("Failed to do fseek at offset %ld: %s!\n", file_offset,
           strerror(errno));
    return -1;
  }
  // for (i = 0; i < PAGEMAP_ENTRY; i++) {
  size_t nread = 0;
  while (nread < sizeof(data)) {
    uint8_t *ptr = ((uint8_t *)&data) + nread;
    status = read(fd, ptr, sizeof(data) - nread);
    if (status == -1) {
      printf("read pagemap fd %d failed, offset %ld, bytes i %d: %s\n", fd,
             file_offset, i, strerror(errno));
      return -1;
    } else if (status == 0) {
      printf("read_pagemap eof\n");
      return -1;
    }
    nread += status;
  }
  entry->pfn = data & (((uint64_t)1 << 54) - 1);
  entry->soft_dirty = (data >> 54) & 1;
  entry->file_page = (data >> 61) & 1;
  entry->swapped = (data >> 62) & 1;
  entry->present = (data >> 63) & 1;
  return 0;
}
