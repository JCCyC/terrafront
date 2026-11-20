#!/usr/bin/env python3
"""The game's text font, U-boat Killer's (images/font.png), to build/font.inc.

font.png is 256x12: two rows of 32 glyphs, 8x6 px each, for ASCII 32..95
(space .. underscore: capitals, digits, punctuation), black letters on
blue, as U-boat Killer prints them on its sky: a black pixel is a set bit
(here drawn in the text's colour), any other colour is clear. Emits FONT (64 glyphs, FONT_ROWS = 6 bytes each, top row
first); print_text puts a glyph's rows on its cell's lines 0..5, lines 6
and 7 blank.

python3 font.py --raw prints the 384 bytes in hex instead, for test.tcl.
"""
import sys
from PIL import Image

PNG = 'images/font.png'
ROWS = 6


def glyphs(png):
    im = Image.open(png).convert('RGB')
    if im.size != (256, 12):
        sys.exit(f'{png}: {im.size[0]}x{im.size[1]}, want 256x12')
    out = []
    for ch in range(32, 96):
        x0, y0 = (ch - 32) % 32 * 8, (ch - 32) // 32 * ROWS
        rows = []
        for y in range(ROWS):
            b = 0
            for x in range(8):
                b = (b << 1) | int(im.getpixel((x0 + x, y0 + y)) == (0, 0, 0))
            rows.append(b)
        out.append(rows)
    return out


def main():
    g = glyphs(PNG)
    if sys.argv[1:] == ['--raw']:
        print(' '.join(f'{b:02x}' for rows in g for b in rows))
        return
    print(f'; {PNG}: ASCII 32..95, {ROWS} rows a glyph (font.py)')
    print(f'FONT_ROWS       equ {ROWS}')
    print('FONT:')
    for ch, rows in zip(range(32, 96), g):
        print('        db ' + ', '.join(f'{b:3d}' for b in rows) + f'   ; {chr(ch)!r}')


if __name__ == '__main__':
    main()
