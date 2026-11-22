#!/usr/bin/env python3
"""Set the license lines of a Terra Front ROM; write the result to stdout.

    ./licenserom.py terrafnt.rom "LICENSED TO" "JOHN DOE" >terrafnt-johns-copy.rom

The source file is left alone. Each line holds up to 32 characters of the
game's font (ASCII 20h-5Fh: capitals, digits, punctuation); lowercase is
turned into capitals. An empty line shows nothing.
"""

import os
import sys

# Must match main.asm (LICENSE_TEXT at 4014h, LICENSE_LEN, EGG_KEY, EGG_KEY_STEP).
# licensebin.py uses these and the functions below too.
LICENSE_OFS = 0x14
LICENSE_LEN = 32
EGG_KEY = 0xA7
EGG_KEY_STEP = 0x3B


# licensezip.py names the file in the zip here ("terrafnt.rom: ")
member = ""


def fail(msg):
    sys.exit(f"{os.path.basename(sys.argv[0])}: {member}{msg}")


def read_source(path):
    """Return the file's bytes, or fail with a short message (missing, unreadable...)."""
    try:
        with open(path, "rb") as f:
            return bytearray(f.read())
    except OSError as e:
        fail(f"{path}: {e.strerror.lower() if e.strerror else e}")


def crypt(data):
    """egg_text's XOR; it undoes itself."""
    return bytes(b ^ ((EGG_KEY + i * EGG_KEY_STEP) & 0xFF) for i, b in enumerate(data))


def check_game(code, what, base):
    """code: the game from its "AB" header on; base: its address."""
    for s in (b"PRESS SPACE OR FIRE TO BEGIN", b"JCCYC"):
        if s not in code:
            fail(f'"{s.decode()}" not found: not a Terra Front {what}')
    # the lines there now must decode to font text, or this version has none
    for n in range(2):
        ofs = LICENSE_OFS + n * LICENSE_LEN
        if not all(0x20 <= b < 0x60 for b in crypt(code[ofs:ofs + LICENSE_LEN])):
            fail(f"no license lines at {base + LICENSE_OFS:04X}h: an older version of the game?")


def check_rom(rom):
    if len(rom) not in (16384, 32768):
        fail(f"{len(rom)} bytes: not a 16 KB or 32 KB ROM")
    init = rom[2] | rom[3] << 8
    if rom[:2] != b"AB" or not (init == 0 or 0x4000 <= init < 0xC000):
        fail("no MSX cartridge header (AB, init address)")
    check_game(rom, "ROM", 0x4000)


def set_lines(code, lines):
    """Write the two license lines into code (a bytearray, from "AB" on)."""
    for n, line in enumerate(lines):
        ofs = LICENSE_OFS + n * LICENSE_LEN
        code[ofs:ofs + LICENSE_LEN] = encode(line)


def license_rom(rom, lines):
    """Check rom (a bytearray) and write the two lines into it."""
    check_rom(rom)
    set_lines(rom, lines)
    return rom


def encode(line):
    line = line.upper()
    if len(line) > LICENSE_LEN:
        fail(f'"{line}" is longer than {LICENSE_LEN} characters')
    bad = sorted({c for c in line if not 0x20 <= ord(c) < 0x60})
    if bad:
        fail(f'"{line}": the game\'s font lacks {" ".join(bad)}')
    return crypt(line.ljust(LICENSE_LEN).encode("ascii"))


def main():
    if len(sys.argv) != 4:
        fail(f"usage: {sys.argv[0]} ROM LINE1 LINE2 >OUT.ROM")
    if sys.stdout.isatty():
        fail("refusing to write a ROM to the terminal; redirect stdout")
    rom = read_source(sys.argv[1])
    sys.stdout.buffer.write(license_rom(rom, sys.argv[2:4]))


if __name__ == "__main__":
    main()
