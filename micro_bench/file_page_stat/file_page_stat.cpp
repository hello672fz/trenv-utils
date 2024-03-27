#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "pagemap.h"
#include "pmparser.h"

using std::map;
using std::set;
using std::string;
using std::vector;

struct file_page_stat {
  unsigned long total_file_page_num; // this contains those not in memory
  unsigned long in_mem_file_page_num;
  unsigned long ro_file_page_num; // read only file pages (in memory)
  unsigned long wr_file_page_num; // been written file pages
};

// filename -> set{page_offset_within_file}
static map<string, set<unsigned long long>> in_mem_file_info;
// filename -> vec{(offset, length)}
static map<string, vector<std::pair<unsigned long long, unsigned long long>>>
    file_info;

static int special_mapping(char *back_file) {
  if (strcmp(back_file, "[heap]") == 0) {
    return 1;
  } else if (strcmp(back_file, "[stack]") == 0) {
    return 1;
  } else if (strcmp(back_file, "[heap]") == 0) {
    return 1;
  } else if (strcmp(back_file, "[vdso]") == 0) {
    return 1;
  } else if (strcmp(back_file, "[vvar]") == 0) {
    return 1;
  } else if (strcmp(back_file, "[vsyscall]") == 0) {
    return 1;
  }
  return 0;
}

int main(int argc, char *argv[]) {
  int pid, pagemap_fd, ret;
  char pagemap_path[1024];
  procmaps_iterator *maps;
  procmaps_struct *maps_entry;
  struct file_page_stat stat_result;
  memset(&stat_result, 0, sizeof(stat_result));

  if (argc != 3) {
    printf("Usage: %s <PID> <PREFIX>\n", argv[0]);
    exit(EXIT_FAILURE);
  }
  pid = atoi(argv[1]);
  printf("start check PID %d\n", pid);
  sprintf(pagemap_path, "/proc/%d/pagemap", pid);
  pagemap_fd = open(pagemap_path, O_RDONLY);
  if (pagemap_fd < 0) {
    perror("open pagemap file failed");
    exit(EXIT_FAILURE);
  }
  maps = pmparser_parse(pid);
  if (maps == NULL) {
    printf("[map]: cannot parse the memory map of %d\n", pid);
    exit(EXIT_FAILURE);
  }

  while ((maps_entry = pmparser_next(maps)) != NULL) {
    // we only cares about file mappings
    if (strlen(maps_entry->pathname) == 0 ||
        special_mapping(maps_entry->pathname))
      continue;
    // else
    //   pmparser_print(maps_entry, 0);

    uint64_t vaddr = (uint64_t)maps_entry->addr_start;
    uint64_t end = (uint64_t)maps_entry->addr_end;
    pagemap_entry_t pagemap_entry;
    string filename(maps_entry->pathname);
    if ((end - vaddr) != maps_entry->length || maps_entry->length == 0) {
      printf("weird maps entry\n");
      exit(EXIT_FAILURE);
    }
    {
      auto &v = file_info[filename];
      v.emplace_back(maps_entry->offset, maps_entry->length);
    }

    if ((vaddr & (getpagesize() - 1)) != 0) {
      printf("Warn: not aligned addr %ld\n", vaddr);
    }
    for (; vaddr < end; vaddr += getpagesize()) {
      stat_result.total_file_page_num += 1;
      ret = read_pagemap(pagemap_fd, vaddr, &pagemap_entry);
      if (ret) {
        printf("read_pagemap error\n");
        exit(EXIT_FAILURE);
      }
      // parse entry
      if (pagemap_entry.present) {
        stat_result.in_mem_file_page_num += 1;
        if (pagemap_entry.file_page) {
          // only record file page (read-only)
          // as for written page we cannot get it content easily
          // we just think they are different
          set<unsigned long long> &page_offset = in_mem_file_info[filename];
          page_offset.insert(vaddr - (uint64_t)maps_entry->addr_start +
                             maps_entry->offset);
          stat_result.ro_file_page_num += 1;
        } else {
          stat_result.wr_file_page_num += 1;
        }
      }
    }
  }

  printf("[PID %d] Total %ld file page: In Mem %ld , RO %ld, WR %ld\n", pid,
         stat_result.total_file_page_num, stat_result.in_mem_file_page_num,
         stat_result.ro_file_page_num, stat_result.wr_file_page_num);
  // dump page_info to file
  string prefix(argv[2]);
  printf("start to dump file_info size %ld\n", file_info.size());
  std::ofstream out(prefix + "-" + argv[1] + ".dat");

  out << stat_result.total_file_page_num << " "
      << stat_result.in_mem_file_page_num << " " << stat_result.ro_file_page_num
      << " " << stat_result.wr_file_page_num << "\n";
  out << "in mem file info\n";
  // one file per line
  for (auto &kv : in_mem_file_info) {
    out << kv.first << " ";
    for (auto offset : kv.second) {
      out << offset << " ";
    }
    out << "\n";
  }
  out << "file info\n";
  for (auto &kv : file_info) {
    out << kv.first << " ";
    for (auto pair : kv.second) {
      out << pair.first << " " << pair.second << " ";
    }
    out << "\n";
  }
  out.close();

  // mandatory: should free the list
  pmparser_free(maps);

  return 0;
}
