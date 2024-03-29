import os
from typing import Dict, List
from tabulate import tabulate
from tqdm import tqdm, trange
import re

LOG_PATH = "/var/lib/faasd/checkpoints/criu-r-workdir"
IMAGES = [
    "h-hello-world",
    "h-memory",
    "pyaes",
    "image-processing",
    "image-recognition",
    "video-processing",
    "chameleon",
    "dynamic-html",
    "crypto",
    "image-flip-rotate",
    "json-serde",
    "js-json-serde",
    "pagerank",
]
PAGE_SIZE = 4096


def get_image_name(id: str):
    res = re.match(r"(.*?)-\d+$", id)
    if res is None:
        raise RuntimeError(f"no valid instance id {id}")
    return res.group(1)


def get_uffds(line: str):
    res = re.search(r"Received PID: (\d+), uffd: (\d+)", line)
    if res is None:
        raise RuntimeError(f"no valid uffds line {id}")
    return f"{res.group(1)}-{res.group(2)}"


def update_nr_page(stat: dict[str, int], uffd: str, nr: int):
    if uffd not in stat:
        stat[uffd] = nr
    else:
        stat[uffd] = max(nr, stat[uffd])


class ParseResult:
    def __init__(self, name, lazy_load_pages, cow_pages, total_pages):
        self.name = name
        self.lazy_load_pages = lazy_load_pages
        self.cow_pages = cow_pages
        self.total_pages = total_pages


def parse(path: str):
    print(f"start parsing {path}")
    name = get_image_name(os.path.basename(path))
    cow_pages = {}
    lazy_pages = {}
    total_pages = {}
    wp_address: dict[str, set] = {}
    with open(os.path.join(path, "lazy-page-daemon.log"), "r") as f:
        for line in f:
            res = re.search(r"uffd: (\d+-\d+): #PF \(write-protect\) at (0x[0-9a-f]+)", line)
            if res is not None:
                uffd = res.group(1)
                addr = res.group(2)
                if uffd not in wp_address:
                    wp_address[uffd] = set()
                wp_address[uffd].add(addr)
            res = re.search(r"uffd: (\d+-\d+): uffd write protect pages: (\d+)/(\d+)", line)
            if res is not None:
                uffd = res.group(1)
                cow_nr_pg = int(res.group(2))
                total_nr_pg = int(res.group(3))
                update_nr_page(cow_pages, uffd, cow_nr_pg)
                update_nr_page(total_pages, uffd, total_nr_pg)
                continue
            res = re.search(r"uffd: (\d+-\d+): uffd copied pages: (\d+)/(\d+)", line)
            if res is not None:
                uffd = res.group(1)
                lazy_nr_pg = int(res.group(2))
                total_nr_pg = int(res.group(3))
                update_nr_page(lazy_pages, uffd, lazy_nr_pg)
                update_nr_page(total_pages, uffd, total_nr_pg)
    total_cow = sum(cow_pages.values())
    total_lazy = sum(lazy_pages.values())
    total = sum(total_pages.values())
    print(total_cow, sum([len(x) for x in wp_address.values()]))
    # assert total_cow == sum([len(x) for x in wp_address.values()])
    total_cow = sum([len(x) for x in wp_address.values()])
    return ParseResult(name, total_lazy, total_cow, total)


if __name__ == "__main__":
    table = []
    for dir in os.listdir(LOG_PATH):
        path = os.path.join(LOG_PATH, dir)
        if os.path.isdir(path):
            res = parse(path)
            lazy_ratio = res.lazy_load_pages / res.total_pages
            cow_ratio = res.cow_pages / res.total_pages
            table.append([res.name, res.lazy_load_pages, res.cow_pages, res.total_pages, f"{lazy_ratio:.2%}", f"{cow_ratio:.2%}"])
    print(tabulate(table, headers=["Name", "Lazy Pages", "COW Pages", "Total Pages", "Lazy Ratio", "COW Ratio"]))


# (00.210626) uffd: 11-9: uffd write protect pages: 1/91548
# (00.210714) uffd: 11-9: uffd copied pages: 2/91548
# (121.67710) uffd: 1-9: #PF (write-protect) at 0xc0002e7000
