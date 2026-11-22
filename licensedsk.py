#!/usr/bin/env python3
"""Set the license lines of the TERRAFNT.BIN on a Terra Front disk image;
write the result to stdout.

    ./licensedsk.py terrafnt.dsk "LICENSED TO" "JOHN DOE" >terrafnt-johns-copy.dsk

The same as licensebin.py, for the BIN inside a disk image (FAT12, as an
MSX formats it): the source file is left alone, each line holds up to 32
characters of the game's font (ASCII 20h-5Fh: capitals, digits,
punctuation), lowercase is turned into capitals, and an empty line shows
nothing. The file keeps its size and clusters; only its bytes change.
"""

import struct
import sys

from licensebin import license_bin
from licenserom import fail, read_source

BIN_NAME = b"TERRAFNT" + b"BIN"     # 8.3 directory entry name


def geometry(disk):
    """Return (sector size, cluster size, FAT offset, root offset, root entries, data offset)."""
    if len(disk) < 512 or disk[0] not in (0xEB, 0xE9):
        fail("no MSX boot sector: not a disk image")
    (sec, spc, reserved, nfats, root_entries, total, _,
     fat_secs) = struct.unpack("<HBHBHHBH", disk[11:24])
    if sec not in (128, 256, 512, 1024) or not spc or not nfats or not fat_secs \
            or total * sec != len(disk):
        fail(f"{len(disk)} bytes: the boot sector's geometry doesn't fit the image")
    fat = reserved * sec
    root = fat + nfats * fat_secs * sec
    data = root + (root_entries * 32 + sec - 1) // sec * sec
    return sec, spc * sec, fat, root, root_entries, data


def fat12(disk, fat, n):
    """Next cluster after n."""
    ofs = fat + n * 3 // 2
    v = disk[ofs] | disk[ofs + 1] << 8
    return v >> 4 if n & 1 else v & 0xFFF


def find_bin(disk, root, root_entries):
    """Return (first cluster, size) of TERRAFNT.BIN in the root directory."""
    for i in range(root_entries):
        e = disk[root + i * 32:root + i * 32 + 32]
        if e[0] == 0:
            break
        if e[0] == 0xE5 or e[11] & 0x18:        # deleted, volume label, directory
            continue
        if e[:11] == BIN_NAME:
            return struct.unpack("<H", e[26:28])[0], struct.unpack("<I", e[28:32])[0]
    fail("no TERRAFNT.BIN on the disk: not a Terra Front disk")


def bin_spans(disk, geo, cluster, size):
    """The file's (offset, length) pieces in the image, following the FAT chain."""
    _, csize, fat, _, _, data = geo
    clusters = (len(disk) - data) // csize
    spans, left, seen = [], size, set()
    while left > 0:
        if not 2 <= cluster < clusters + 2 or cluster in seen:
            fail("TERRAFNT.BIN's cluster chain is broken")
        seen.add(cluster)
        n = min(left, csize)
        spans.append((data + (cluster - 2) * csize, n))
        left -= n
        cluster = fat12(disk, fat, cluster)
    return spans


def license_dsk(disk, lines):
    """Check disk (a bytearray, the whole image) and write the two lines into its BIN."""
    geo = geometry(disk)
    spans = bin_spans(disk, geo, *find_bin(disk, geo[3], geo[4]))
    data = license_bin(bytearray(b"".join(disk[o:o + n] for o, n in spans)), lines)
    pos = 0
    for o, n in spans:
        disk[o:o + n] = data[pos:pos + n]
        pos += n
    return disk


def main():
    if len(sys.argv) != 4:
        fail(f"usage: {sys.argv[0]} DSK LINE1 LINE2 >OUT.DSK")
    if sys.stdout.isatty():
        fail("refusing to write a disk image to the terminal; redirect stdout")
    disk = read_source(sys.argv[1])
    sys.stdout.buffer.write(license_dsk(disk, sys.argv[2:4]))


if __name__ == "__main__":
    main()
