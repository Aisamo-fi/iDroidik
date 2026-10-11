#!/usr/bin/env python3
"""Inspect and rewrite Android dynamic-partition (liblp) metadata inside the Sandcastle nand image.

The nand file is a GPT disk (4K blocks) with partitions `vbmeta` and `super`. `super` holds liblp
metadata (geometry at +4096, metadata slots from +12288) describing logical partitions as extents
in 512-byte sectors relative to the start of `super`.

  lpsuper.py dump NAND
  lpsuper.py replace NAND PARTITION IMAGE     # place IMAGE as PARTITION in free space, update metadata
"""
import hashlib
import struct
import sys

GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030
SECTOR = 512


def gpt_partitions(f):
    f.seek(4096)
    hdr = f.read(92)
    assert hdr[:8] == b"EFI PART", "no GPT"
    first_lba, count, entry_size = struct.unpack("<QII", hdr[72:88])
    f.seek(first_lba * 4096)
    parts = {}
    for _ in range(count):
        e = f.read(entry_size)
        if e[:16] == b"\0" * 16:
            continue
        start, end = struct.unpack("<QQ", e[32:48])
        name = e[56:128].decode("utf-16le").rstrip("\0")
        parts[name] = (start * 4096, (end - start + 1) * 4096)
    return parts


class Metadata:
    PART = struct.Struct("<36sIIII")        # name, attributes, first_extent_index, num_extents, group_index
    EXTENT = struct.Struct("<QIQI")          # num_sectors, target_type, target_data, target_source
    GROUP = struct.Struct("<36sIQ")          # name, flags, maximum_size
    BLOCKDEV = struct.Struct("<QIIQ36sI")    # first_logical_sector, alignment, alignment_offset, size, name, flags

    def __init__(self, f, super_off):
        self.f, self.super_off = f, super_off
        f.seek(super_off + 4096)
        g = f.read(4096)
        magic, _size = struct.unpack("<II", g[:8])
        assert magic == GEOMETRY_MAGIC, "bad geometry magic"
        self.max_size, self.slots, self.lbs = struct.unpack("<III", g[40:52])
        f.seek(super_off + 12288)
        blob = f.read(self.max_size)
        (magic, self.major, self.minor, self.header_size) = struct.unpack("<IHHI", blob[:12])
        assert magic == HEADER_MAGIC, "bad header magic"
        self.header = bytearray(blob[: self.header_size])
        tables_size = struct.unpack("<I", blob[44:48])[0]
        tables = blob[self.header_size : self.header_size + tables_size]
        assert hashlib.sha256(tables).digest() == bytes(blob[48:80]), "tables checksum mismatch"
        descs = struct.unpack("<" + "III" * 4, blob[80:128])
        self.desc = [descs[i : i + 3] for i in range(0, 12, 3)]  # partitions, extents, groups, block devices

        def read_table(i, st):
            off, n, size = self.desc[i]
            assert size == st.size, f"unexpected entry size {size} vs {st.size}"
            return [list(st.unpack_from(tables, off + k * size)) for k in range(n)]

        self.partitions = read_table(0, self.PART)
        self.extents = read_table(1, self.EXTENT)
        self.groups = read_table(2, self.GROUP)
        self.blockdevs = read_table(3, self.BLOCKDEV)

    @staticmethod
    def name(raw):
        return raw.rstrip(b"\0").decode()

    def dump(self):
        print(f"liblp {self.major}.{self.minor}, header {self.header_size}, max {self.max_size}, slots {self.slots}")
        for b in self.blockdevs:
            print(f"blockdev {self.name(b[4])}: first sector {b[0]}, size {b[3]} ({b[3] // SECTOR} sectors)")
        for g in self.groups:
            print(f"group {self.name(g[0])}: max {g[2]}")
        for p in self.partitions:
            exts = self.extents[p[2] : p[2] + p[3]]
            desc = ", ".join(f"[{e[2]}..{e[2] + e[0]}) {e[0] * SECTOR // 2**20} MiB" for e in exts)
            print(f"partition {self.name(p[0])} attr={p[1]} group={self.name(self.groups[p[4]][0])}: {desc}")

    def serialize(self):
        tables = bytearray()
        offsets = []
        for rows, st in ((self.partitions, self.PART), (self.extents, self.EXTENT),
                         (self.groups, self.GROUP), (self.blockdevs, self.BLOCKDEV)):
            offsets.append((len(tables), len(rows), st.size))
            for r in rows:
                tables += st.pack(*r)
        hdr = bytearray(self.header)
        struct.pack_into("<I", hdr, 44, len(tables))
        hdr[48:80] = hashlib.sha256(tables).digest()
        struct.pack_into("<" + "III" * 4, hdr, 80, *[x for o in offsets for x in o])
        hdr[12:44] = b"\0" * 32
        hdr[12:44] = hashlib.sha256(hdr).digest()
        blob = bytes(hdr) + bytes(tables)
        assert len(blob) <= self.max_size
        return blob

    def write(self):
        blob = self.serialize().ljust(self.max_size, b"\0")
        # primary slots then backup slots
        for i in range(self.slots * 2):
            self.f.seek(self.super_off + 12288 + i * self.max_size)
            self.f.write(blob)

    def used_ranges(self):
        return sorted((e[2], e[2] + e[0]) for e in self.extents)


def align_up(x, a):
    return (x + a - 1) // a * a


def replace(nand, part_name, image):
    with open(nand, "r+b") as f:
        parts = gpt_partitions(f)
        super_off, super_size = parts["super"]
        md = Metadata(f, super_off)
        pidx = next(i for i, p in enumerate(md.partitions) if md.name(p[0]) == part_name)
        p = md.partitions[pidx]
        assert p[3] == 1, "only single-extent partitions supported"
        others = [r for i, r in enumerate(md.used_ranges())]
        own = md.extents[p[2]]
        others.remove((own[2], own[2] + own[0]))
        blockdev = md.blockdevs[0]
        first, dev_sectors = blockdev[0], blockdev[3] // SECTOR
        with open(image, "rb") as img:
            img.seek(0, 2)
            img_size = img.tell()
        need = align_up(align_up(img_size, SECTOR) // SECTOR, 2048)
        # first gap (aligned to 1 MiB) that fits, scanning after the metadata area
        cursor, start = first, None
        for lo, hi in sorted(others) + [(dev_sectors, dev_sectors)]:
            if lo - align_up(cursor, 2048) >= need:
                start = align_up(cursor, 2048)
                break
            cursor = max(cursor, hi)
        assert start is not None, f"no free space for {need} sectors"
        group = md.groups[p[4]]
        total = sum(md.extents[q[2]][0] for q in md.partitions if q[4] == p[4] and q is not p) + need
        assert group[2] == 0 or total * SECTOR <= group[2], "group maximum size exceeded"
        print(f"{part_name}: {own[0]} sectors @ {own[2]} -> {need} sectors @ {start} ({img_size} bytes)")
        with open(image, "rb") as img:
            f.seek(super_off + start * SECTOR)
            while True:
                chunk = img.read(16 * 2**20)
                if not chunk:
                    break
                f.write(chunk)
            pad = need * SECTOR - img_size
            f.write(b"\0" * pad)
        own[0], own[2] = need, start
        md.write()
    with open(nand, "rb") as f:
        Metadata(f, gpt_partitions(f)["super"][0]).dump()


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "dump":
        with open(sys.argv[2], "rb") as fh:
            Metadata(fh, gpt_partitions(fh)["super"][0]).dump()
    elif len(sys.argv) == 5 and sys.argv[1] == "replace":
        replace(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print(__doc__)
        sys.exit(1)
