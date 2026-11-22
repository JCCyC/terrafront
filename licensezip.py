#!/usr/bin/env python3
"""Set the license lines of the ROM, the BIN and the disk image in a
Terra Front zip; write the result to stdout.

    ./licensezip.py terrafnt_0_9_1.zip "LICENSED TO" "JOHN DOE" >terrafnt-johns-copy.zip

The same as licenserom.py, licensebin.py and licensedsk.py, for all three
files at once: the source zip is left alone, each line holds up to 32
characters of the game's font (ASCII 20h-5Fh: capitals, digits,
punctuation), lowercase is turned into capitals, and an empty line shows
nothing. The zip must hold exactly one .rom, one .bin and one .dsk; every
member keeps its name, date and attributes, the others are copied as
they are.
"""

import io
import os
import sys
import zipfile

import licenserom
from licensebin import license_bin
from licensedsk import license_dsk
from licenserom import encode, fail, license_rom, read_source

LICENSERS = {".rom": license_rom, ".bin": license_bin, ".dsk": license_dsk}


def main():
    if len(sys.argv) != 4:
        fail(f"usage: {sys.argv[0]} ZIP LINE1 LINE2 >OUT.ZIP")
    if sys.stdout.isatty():
        fail("refusing to write a zip to the terminal; redirect stdout")
    lines = sys.argv[2:4]
    for line in lines:
        encode(line)        # fails on a bad line before naming a file
    try:
        src = zipfile.ZipFile(io.BytesIO(read_source(sys.argv[1])))
    except zipfile.BadZipFile:
        fail(f"{sys.argv[1]}: not a zip file")
    with src:
        infos = src.infolist()
        for ext in LICENSERS:
            found = [i.filename for i in infos if os.path.splitext(i.filename)[1].lower() == ext]
            if len(found) != 1:
                fail(f"{len(found)} {ext} files in the zip, not 1: not a Terra Front zip")
        out = io.BytesIO()
        with zipfile.ZipFile(out, "w") as dst:
            dst.comment = src.comment
            for info in infos:
                data = src.read(info)
                license = LICENSERS.get(os.path.splitext(info.filename)[1].lower())
                if license:
                    licenserom.member = f"{info.filename}: "
                    data = license(bytearray(data), lines)
                    licenserom.member = ""
                dst.writestr(info, data, compresslevel=9)
    sys.stdout.buffer.write(out.getvalue())


if __name__ == "__main__":
    main()
