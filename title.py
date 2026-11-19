#!/usr/bin/env python3
"""The splash screen from images/title.png (256x192, MSX1 colours, at most
two in each 8x1 byte, as SCREEN 2 needs), to build/title.inc.

SCREEN 2's pattern and colour tables, each as 24 rows of characters (256
bytes each, in VRAM order) packed with RLE, and a table of where each row
starts (TITLE_PAT_ROWS, TITLE_COL_ROWS: 24 words), so that one row can be
unpacked alone (the blinking text's colours). A byte's colours: black, if
it has it, is the background (its pixels 0 in the pattern); one colour
alone is the foreground of a full byte (black alone: 0 on black).

RLE: n = 1..127: n bytes follow as they are; n = 128..255: the next byte
n-126 times (2..129); 0 ends the row.

python3 title.py --raw prints the unpacked tables instead (6144 pattern
bytes, then 6144 colour bytes, in hex), for test.tcl.
"""
import sys
from PIL import Image
from png2spr import nearest

PNG = 'images/title.png'
BLACK = 1


def tables(png):
    im = Image.open(png).convert('RGB')
    if im.size != (256, 192):
        sys.exit(f'{png}: {im.size[0]}x{im.size[1]}, want 256x192')
    col = {}
    pat, clr = [], []
    for row in range(24):
        for cx in range(32):
            for y in range(row * 8, row * 8 + 8):
                px = []
                for x in range(cx * 8, cx * 8 + 8):
                    rgb = im.getpixel((x, y))
                    if rgb not in col:
                        col[rgb] = nearest(rgb) if rgb != (0, 0, 0) else BLACK
                    px.append(col[rgb])
                cs = sorted(set(px))
                if len(cs) > 2:
                    sys.exit(f'{png}: {len(cs)} colours in the byte at ({cx * 8}, {y})')
                if cs == [BLACK]:
                    fg, bg = BLACK, BLACK
                elif BLACK in cs:
                    fg, bg = max(cs), BLACK
                elif len(cs) == 1:
                    fg, bg = cs[0], BLACK
                else:
                    bg, fg = cs
                pat.append(sum(0x80 >> i for i, c in enumerate(px) if c == fg and fg != bg))
                clr.append(fg * 16 + bg)
    return pat, clr


def rle(data):
    out, lit, i = [], [], 0
    while i < len(data):
        n = 1
        while i + n < len(data) and data[i + n] == data[i] and n < 129:
            n += 1
        if n >= 2:
            if lit:
                out += [len(lit)] + lit
                lit = []
            out += [n + 126, data[i]]
            i += n
        else:
            lit.append(data[i])
            i += 1
            if len(lit) == 127:
                out += [127] + lit
                lit = []
    if lit:
        out += [len(lit)] + lit
    return out + [0]


def emit(name, table):
    print(f'{name}_ROWS:')
    for r in range(24):
        print(f'        dw {name}_{r}')
    size = 0
    for r in range(24):
        packed = rle(table[r * 256:(r + 1) * 256])
        size += len(packed)
        print(f'{name}_{r}:')
        for i in range(0, len(packed), 16):
            print('        db ' + ', '.join(f'{b:3d}' for b in packed[i:i + 16]))
    return size


def main():
    pat, clr = tables(PNG)
    if sys.argv[1:] == ['--raw']:
        print(' '.join(f'{b:02x}' for b in pat + clr))
        return
    print(f'; {PNG}: SCREEN 2 tables, 24 rows of 256 bytes each, RLE (title.py)')
    a = emit('TITLE_PAT', pat)
    b = emit('TITLE_COL', clr)
    print(f'; packed: patterns {a} bytes, colours {b} bytes')


if __name__ == '__main__':
    main()
