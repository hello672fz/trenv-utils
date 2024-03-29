import hashlib
import os
from typing import Dict, List
from tabulate import tabulate
from tqdm import tqdm, trange

IMG_PATH = "/var/lib/faasd/checkpoints/images"
IMAGES = [
    "pyaes",
    "image-processing",
    "image-recognition",
    "video-processing",
    "chameleon",
    "dynamic-html",
    "crypto",
    "image-flip-rotate",
    "h-hello-world",
    "h-memory",
    "json-serde",
    "js-json-serde",
    "pagerank",
]
PAGE_SIZE = 4096


class MemImage:
    def __init__(self, path):
        self.name = os.path.basename(path)

        imgs = []
        for f in os.listdir(path):
            if f.startswith("pages-") and f.endswith(".img"):
                imgs.append(os.path.join(path, f))
        content = bytearray()
        for img_path in imgs:
            with open(img_path, "rb") as f:
                img = f.read()
                if len(img) % PAGE_SIZE != 0:
                    raise RuntimeError(f"image at {path} is not aligned to 4096 bytes")
                content += img

        page_num = len(content) // PAGE_SIZE
        # digest is a dict: key is hash result, value is a list of index to those pages content with this hash
        digest: Dict[str, List[int]] = {}
        # calculate digest
        for i in trange(page_num, desc=f"cal hash for {self.name}"):
            page = content[i * PAGE_SIZE : (i + 1) * PAGE_SIZE]
            if len(page) % PAGE_SIZE != 0:
                raise RuntimeError(f"page at 0x{i*PAGE_SIZE:x} is not aligned to 4096 bytes")
            h = hashlib.md5(page).hexdigest()
            if h not in digest:
                digest[h] = [i]
            else:
                digest[h].append(i)

        self.digest = digest
        self.content = bytes(content)  # immutable

    def page_num(self):
        return len(self.content) // PAGE_SIZE

    def get_page_at(self, idx: int):
        if idx >= self.page_num():
            raise RuntimeError(f"get page at 0x{idx:x} beyond range for {self.name}")
        return self.content[idx * PAGE_SIZE : (idx + 1) * PAGE_SIZE]

    def lookup_num(self, h: str, content: bytes):
        num = 0
        if h in self.digest:
            for page_idx in self.digest[h]:
                if self.get_page_at(page_idx) == content:
                    num += 1
        return num

    def lookup(self, h: str, content: bytes):
        if h in self.digest:
            for page_idx in self.digest[h]:
                if self.get_page_at(page_idx) == content:
                    return True
        return False

    def lookup_exclude(self, h: str, content: bytes, idx: int):
        if h in self.digest:
            for page_idx in self.digest[h]:
                if page_idx != idx and self.get_page_at(page_idx) == content:
                    return True
        return False


if __name__ == "__main__":
    # key value pair
    images: Dict[str, MemImage] = {}
    for img_name in IMAGES:
        path = os.path.join(IMG_PATH, img_name)
        img = MemImage(path)
        images[img.name] = img

    dup: Dict[str, set] = {}
    for img_name in images:
        if img_name not in dup:
            dup[img_name] = set()
        img = images[img_name]
        for digest in tqdm(img.digest, total=len(img.digest), desc=f"cal dup for {img.name}"):
            page_idxs = img.digest[digest]
            for page_idx in page_idxs:
                page = img.get_page_at(page_idx)
                for other_img in images.values():
                    if img.name == other_img.name:
                        if other_img.lookup_exclude(digest, page, page_idx):
                            dup[img.name].add(page_idx)
                            break
                    elif other_img.lookup(digest, page):
                        dup[img.name].add(page_idx)
                        # if we found page in one image, we stop find for this page from other images
                        break

    table = []
    for img_name in dup:
        img_dup_page_num = len(dup[img_name])
        img_page_toal_num = images[img_name].page_num()
        per = img_dup_page_num / img_page_toal_num
        table.append([img_name, img_dup_page_num, img_page_toal_num, f"{per:.2%}"])
    print(tabulate(table, headers=["Image", "Duplicated Pages", "Total Pages", "Duplicated percentage"]))
