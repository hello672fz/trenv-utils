import os
from tabulate import tabulate


class FileInfo:
    def __init__(self, path):
        base = os.path.basename(path)
        function = base.rsplit("-", 1)[0]
        self.function = function
        print(f"initialize function {function} from {path}")
        with open(path, "r") as f:
            first_line = f.readline().strip()
            data = first_line.split(" ")
            self.total_nr = int(data[0], base=10)
            self.in_mem_nr = int(data[1], base=10)
            self.ro_nr = int(data[2], base=10)
            self.wr_nr = int(data[3], base=10)
            self.in_mem: dict[str, set[int]] = {}
            assert f.readline().strip() == "in mem file info"
            while True:
                line = f.readline()
                assert len(line) > 0
                line = line.strip()
                if line == "file info":
                    break
                data = line.split(" ")
                filename = data[0]
                if filename not in self.in_mem:
                    self.in_mem[filename] = set()
                for off in data[1:]:
                    off = int(off, base=10)
                    self.in_mem[filename].add(off)
            # filename -> page offset
            self.file: dict[str, set[int]] = {}
            while True:
                line = f.readline()
                if len(line) == 0:
                    break
                line = line.strip()
                data = line.split(" ")
                filename = data[0]
                if filename not in self.file:
                    self.file[filename] = set()
                nr = len(data[1:])
                assert nr % 2 == 0
                for idx in range(1, nr + 1, 2):
                    start = int(data[idx], base=10)
                    length = int(data[idx + 1], base=10)
                    for addr in range(start, start + length, 4096):
                        self.file[filename].add(addr)

    def merge(self, other: "FileInfo"):
        if self.function != other.function:
            print("cannot merge different func")
            return False
        self.total_nr += other.total_nr
        self.in_mem_nr += other.in_mem_nr
        self.ro_nr += other.ro_nr
        self.wr_nr += other.wr_nr
        for filename in other.in_mem:
            if filename not in self.in_mem:
                self.in_mem[filename] = other.in_mem[filename]
            else:
                self.in_mem[filename] = self.in_mem[filename].union(other.in_mem[filename])
        for filename in other.file:
            if filename not in self.file:
                self.file[filename] = other.file[filename]
            else:
                self.file[filename] = self.file[filename].union(other.file[filename])
        return True

    def in_mem_dup_nr(self, others: list["FileInfo"]):
        dup = set()
        for other in others:
            if self.function == other.function:
                continue
            for filename in self.in_mem:
                if filename not in other.in_mem:
                    continue
                for offset in self.in_mem[filename]:
                    if offset in other.in_mem[filename]:
                        dup.add((filename, offset))
        return len(dup)

    def file_dup_nr(self, others: list["FileInfo"]):
        dup = set()
        for other in others:
            if self.function == other.function:
                continue
            for filename in self.file:
                if filename not in other.file:
                    continue
                for offset in self.file[filename]:
                    if offset in other.file[filename]:
                        dup.add((filename, offset))
        return len(dup)


if __name__ == "__main__":
    file_infos = []
    for dat_file in os.listdir("."):
        if dat_file.endswith(".dat"):
            file_info = FileInfo(dat_file)
            is_merge = False
            for x in file_infos:
                if x.function == file_info.function:
                    assert x.merge(file_info)
                    is_merge = True
            if not is_merge:
                file_infos.append(file_info)

    print(
        tabulate(
            [
                [x.function, x.total_nr, x.in_mem_nr, x.ro_nr, x.wr_nr, x.in_mem_dup_nr(file_infos), x.file_dup_nr(file_infos)]
                for x in file_infos
            ],
            headers=["Name", "Total", "Lazy", "RO", "WR", "In Mem Dup", "Total Dup"],
        )
    )
