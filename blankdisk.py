#!/usr/bin/env python3
"""Write an empty MSX disk image to stdout, with the boot sector of another.

    ./blankdisk.py ../personal-assets/msxdos1-720k.dsk >blank720k.dsk

Only the boot sector (geometry and MSX boot code) is kept: the FATs and the
root directory start empty and every other sector is zeroed, so nothing of
the source disk's files is left in the image.
"""

import struct
import sys


def main():
    if len(sys.argv) != 2 or sys.stdout.isatty():
        sys.exit(f"usage: {sys.argv[0]} SOURCE.DSK >OUT.DSK")
    with open(sys.argv[1], "rb") as f:
        boot = f.read(512)
    (sec_size, _, reserved, nfats, root_entries, total, media,
     fat_secs) = struct.unpack("<HBHBHHBH", boot[11:24])
    if sec_size != 512 or boot[0] not in (0xEB, 0xE9) or not total:
        sys.exit(f"{sys.argv[1]}: no MSX boot sector")
    disk = bytearray(total * sec_size)
    disk[:512] = boot
    for n in range(nfats):
        ofs = (reserved + n * fat_secs) * sec_size
        disk[ofs:ofs + 3] = bytes((media, 0xFF, 0xFF))
    sys.stdout.buffer.write(disk)


if __name__ == "__main__":
    main()
