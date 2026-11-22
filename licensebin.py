#!/usr/bin/env python3
"""Set the license lines of a Terra Front BIN; write the result to stdout.

    ./licensebin.py terrafnt.bin "LICENSED TO" "JOHN DOE" >johns/TERRAFNT.BIN

The same as licenserom.py, for the BLOAD file: the source file is left
alone, each line holds up to 32 characters of the game's font (ASCII
20h-5Fh: capitals, digits, punctuation), lowercase is turned into capitals,
and an empty line shows nothing. Keep the name TERRAFNT.BIN on the disk:
its AUTOEXEC.BAS loads that.
"""

import sys

from licenserom import check_game, fail, read_source, set_lines

HEADER = 7      # FEh, start, end, run address


def check_bin(data):
    """Return the loaded part (from the game's "AB" header on) and its address."""
    if len(data) < HEADER or data[0] != 0xFE:
        fail("no BLOAD header (FEh, start, end, run address)")
    start, end, run = (data[i] | data[i + 1] << 8 for i in (1, 3, 5))
    size = end - start + 1
    if size <= 0 or len(data) < HEADER + size:
        fail(f"BLOAD header says {start:04X}h-{end:04X}h, but the file is {len(data)} bytes")
    code = data[HEADER:HEADER + size]
    init = code[2] | code[3] << 8
    if code[:2] != b"AB" or init != run:
        fail("the game's header (AB, start address) isn't at the load address")
    check_game(code, "BIN", start)
    return code


def license_bin(data, lines):
    """Check data (a bytearray, the whole file) and write the two lines into it."""
    code = check_bin(data)
    set_lines(code, lines)
    data[HEADER:HEADER + len(code)] = code
    return data


def main():
    if len(sys.argv) != 4:
        fail(f"usage: {sys.argv[0]} BIN LINE1 LINE2 >OUT.BIN")
    if sys.stdout.isatty():
        fail("refusing to write a BIN to the terminal; redirect stdout")
    data = read_source(sys.argv[1])
    sys.stdout.buffer.write(license_bin(data, sys.argv[2:4]))


if __name__ == "__main__":
    main()
