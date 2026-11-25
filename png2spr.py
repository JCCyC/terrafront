#!/usr/bin/env python3
"""Player ship sprite from images/player-ship.png (16x16, black = transparent),
and the reserve ship from images/reserve-ship.png (8x8, black = background).

the ship coming in from the right with its woosh lines,
images/player-ship-coming.png (16x16; mirrored for a ship coming from the left),
and the dying ship's three boom images, images/player-ship-boom-1..3.png
(SHIP_ART_W x 16: the ship's art box, placed where the ship's art is).

Writes sjasmplus source to stdout:
  SHIP_PATTERN   32 bytes, the 16x16 sprite layout (left 8 columns, rows 0..15,
                 then the right 8 columns)
  SHIP_COLOR     the MSX1 colour nearest to the art's one colour
  SHIP_ART_L     first column with art (0..15)
  SHIP_ART_W     art width in pixels (first to last column with art)
  SHIP_NOSE_DX   the nose's column (the top row's only pixel) minus SHIP_ART_L
  SHIP_ART_T     first row with art
  SHIP_ART_B     last row with art
  SHIP_ROWS      16 words, the art's rows 0..15 (the sprite's), its left
                 column on bit 15 (for the collision test)
  COMING_R_PATTERN  32 bytes, the ship coming in from the right (sprite layout)
  COMING_L_PATTERN  ... mirrored: coming in from the left
  COMING_COLOR   the MSX1 colour nearest to its art's one colour
  COMING_R_ART_L the ship's art's left column in COMING_R_PATTERN (the ship
                 found by matching images/player-ship.png's art in it)
  COMING_L_ART_L ... in COMING_L_PATTERN
  BOOM_PATTERN   3 x 32 bytes, the boom images in order (sprite layout)
  BOOM_COLOR     the MSX1 colour nearest to their art's one colour (the same in all)
  RESERVE_SHAPE  8 bytes, the reserve ship's rows, its art's left column on bit 7
  RESERVE_COLOR  the MSX1 colour nearest to its art's one colour
  RESERVE_ART_W  its art width in pixels
  ENEMY_PATTERN  ENEMIES x 32 bytes: each enemy (images/enemy-N.png, 8x16,
                 one colour; their colour is set in main.asm) as a pair, a
                 16x16 sprite showing it twice side by side
  ENEMIES        how many
  ENEMY_ROWS     per enemy, its art's first and last rows
  FORM_PAIRS     the formation's pairs (from images/formation-enemy-E-color-C.png,
                 where every pair is enemy E in colour C): dx, dy each, from
                 the formation's top left, top to bottom
  FORM_PAIRS_N   how many
  FORM_X0        the formation's left column in the picture
  FORM_W, FORM_H its size in px
  BOSS_PATTERN   4 x 32 bytes: the boss (images/boss1.png, 64x16, one colour;
                 its colour is set in main.asm) as four 16x16 sprites, left
                 to right
  BOSS_BOOM_PATTERN  3 x 4 x 32 bytes: per boom image (BOOM_PNGS), 4 sprites
                 of BOSS_BOOMS copies of it side by side, spread evenly over
                 the boss's 64 columns (the first at column 0, the last
                 ending on column 63; neighbours overlap)
  BOSS_W, BOSS_H the boss's size in px (its art fills its box)
  BOSS2_PAT      2 x 64 bytes: Boss2 (images/boss2.png, 64x16, white and one
                 body colour, at most two colours a 8x1 byte, black
                 included) in the SCREEN 2 bitmap: its two rows of 8 cells
  BOSS2_COL      ... their colour bytes: white F1h, the body 01h (its colour,
                 set in main.asm, in the high nibble), black F1h
  BOSS2_PATTERN  4 x 32 bytes: its art as four 16x16 sprites (as
                 BOSS_PATTERN: the hit tests)
  BOSS2_LAST     its art's last row
  ENEMY_COLS     per enemy, its art's first and last columns
"""
import glob
import re
import sys
from PIL import Image

PNG = 'images/player-ship.png'
COMING_PNG = 'images/player-ship-coming.png'
RESERVE_PNG = 'images/reserve-ship.png'
ENEMY_PNG = 'images/enemy-{}.png'
FORMATION_PNG = glob.glob('images/formation-enemy-*-color-*.png')
BOOM_PNGS = [f'images/player-ship-boom-{i}.png' for i in (1, 2, 3)]
BOSS_PNG = 'images/boss1.png'
BOSS_BOOMS = 8
BOSS2_PNG = 'images/boss2.png'

# TMS9918 palette (approximate RGB), colour 1..15
MSX1 = {
    1: (0, 0, 0), 2: (33, 200, 66), 3: (94, 220, 120), 4: (84, 85, 237),
    5: (125, 118, 252), 6: (212, 82, 77), 7: (66, 235, 245), 8: (252, 85, 84),
    9: (255, 121, 120), 10: (212, 193, 84), 11: (230, 206, 128),
    12: (33, 176, 59), 13: (201, 91, 186), 14: (204, 204, 204), 15: (255, 255, 255),
}


def nearest(rgb):
    return min(MSX1, key=lambda c: sum((a - b) ** 2 for a, b in zip(MSX1[c], rgb)))


def load(png, size, width=None):
    """The art's pixels (on[y][x]) and its MSX1 colour"""
    width = width or size
    im = Image.open(png).convert('RGB')
    assert im.size == (width, size), f'{png}: {im.size}, want {width}x{size}'
    on = [[im.getpixel((x, y)) != (0, 0, 0) for x in range(width)] for y in range(size)]
    colours = {im.getpixel((x, y)) for y in range(size) for x in range(width) if on[y][x]}
    assert len(colours) == 1, f'{png}: the art must have one colour, has {colours}'
    colour = nearest(colours.pop())
    assert colour != 1, f'{png}: the art is black: it would not show'
    return on, colour


def sprite_pattern(on):
    """The 32 bytes of a 16x16 sprite: left 8 columns, rows 0..15, then the right 8"""
    return [sum(0x80 >> i for i in range(8) if on[y][half + i]) for half in (0, 8) for y in range(16)]


def print_pattern(label, pattern):
    print(label if label.startswith(';') else label + ':')
    for i in range(0, 32, 8):
        print('        db ' + ','.join(f'{b:#04x}' for b in pattern[i:i + 8]))


def main():
    on, colour = load(PNG, 16)

    cols = [x for x in range(16) if any(on[y][x] for y in range(16))]
    rows = [y for y in range(16) if any(on[y])]
    top = [x for x in range(16) if on[rows[0]][x]]
    assert len(top) == 1, f'{PNG}: the top row should be the nose, one pixel; has {top}'

    pattern = sprite_pattern(on)
    ship = on

    print('; Generated by png2spr.py from ' + PNG + ': do not edit')
    print(f'SHIP_COLOR      equ {colour}')
    print(f'SHIP_ART_L      equ {cols[0]}')
    print(f'SHIP_ART_W      equ {cols[-1] - cols[0] + 1}')
    print(f'SHIP_ART_T      equ {rows[0]}')
    print(f'SHIP_ART_B      equ {rows[-1]}')
    print(f'SHIP_NOSE_DX    equ {top[0] - cols[0]}')
    print_pattern('SHIP_PATTERN', pattern)
    assert cols[-1] - cols[0] < 16
    ship_rows = [sum(0x8000 >> (x - cols[0]) for x in cols if on[y][x]) for y in range(16)]

    # The coming ship: the plain ship's art (same rows) plus the woosh lines
    # trailing on its right (they may start in the art's box, beside the
    # nose); where the ship's art is: the leftmost place all its pixels are
    coming, ccolour = load(COMING_PNG, 16)
    art = [(x - cols[0], y) for y in range(16) for x in range(16) if ship[y][x]]
    fits = [dx for dx in range(16 - (cols[-1] - cols[0]))
            if all(coming[y][dx + x] for x, y in art)]
    assert fits, f'{COMING_PNG}: the ship of {PNG} is not in it (at the same rows)'
    dx = fits[0]
    mirrored = [row[::-1] for row in coming]
    print(f'COMING_COLOR    equ {ccolour}')
    print(f'COMING_R_ART_L  equ {dx}')
    print(f'COMING_L_ART_L  equ {16 - dx - (cols[-1] - cols[0] + 1)}')
    print_pattern('COMING_R_PATTERN', sprite_pattern(coming))
    print_pattern('COMING_L_PATTERN', sprite_pattern(mirrored))

    # The boom images: the ship's art box, padded to 16 columns where the
    # ship's art is in its sprite
    w = boom_w = cols[-1] - cols[0] + 1
    bcolours = set()
    print('BOOM_PATTERN:')
    for png in BOOM_PNGS:
        on, colour = load(png, 16, w)
        bcolours.add(colour)
        box = [[False] * cols[0] + row + [False] * (16 - cols[0] - w) for row in on]
        print_pattern('; ' + png, sprite_pattern(box))
    assert len(bcolours) == 1, f'{BOOM_PNGS}: the boom images must share one colour, have {bcolours}'
    print(f'BOOM_COLOR      equ {bcolours.pop()}')

    on, colour = load(RESERVE_PNG, 8)
    cols = [x for x in range(8) if any(on[y][x] for y in range(8))]
    shape = [sum(0x80 >> (x - cols[0]) for x in cols if on[y][x]) for y in range(8)]
    print(f'RESERVE_COLOR   equ {colour}')
    print(f'RESERVE_ART_W   equ {cols[-1] - cols[0] + 1}')
    print('RESERVE_SHAPE:')
    print('        db ' + ','.join(f'{b:#04x}' for b in shape))

    enemies = sorted(int(re.search(r'(\d+)\.png$', f).group(1)) for f in glob.glob(ENEMY_PNG.format('*')))
    assert enemies == list(range(len(enemies))), f'enemy images not numbered 0..: {enemies}'
    pairs = []
    rows = []
    ecols = []
    print(f'ENEMIES         equ {len(enemies)}')
    print('ENEMY_PATTERN:')
    for e in enemies:
        on, _ = load(ENEMY_PNG.format(e), 16, 8)
        pair = [row + row for row in on]
        pairs.append(pair)
        lit = [y for y in range(16) if any(on[y])]
        rows.append((lit[0], lit[-1]))
        cl = [x for x in range(8) if any(on[y][x] for y in range(16))]
        ecols.append((cl[0], cl[-1]))
        print_pattern('; ' + ENEMY_PNG.format(e) + ', twice', sprite_pattern(pair))
    print('ENEMY_ROWS:')
    print('        db ' + ', '.join(f'{t},{b}' for t, b in rows))

    # The formation: every 16x16 box in the picture where enemy E's pair
    # is, in colour C, with no other pixel of that colour in the box
    assert len(FORMATION_PNG) == 1, f'want one formation picture, have {FORMATION_PNG}'
    png = FORMATION_PNG[0]
    e, c = map(int, re.search(r'formation-enemy-(\d+)-color-(\d+)\.png$', png).groups())
    im = Image.open(png).convert('RGB')
    w, h = im.size
    px = {(x, y): im.getpixel((x, y)) for y in range(h) for x in range(w)}
    rgb = {v for v in px.values() if v != (0, 0, 0) and nearest(v) == c}
    assert len(rgb) == 1, f'{png}: want one colour nearest MSX1 colour {c}, have {rgb}'
    rgb = rgb.pop()
    lit = {p for p, v in px.items() if v == rgb}
    pair = pairs[e]
    found = []
    for y in range(h - 15):
        for x in range(w - 15):
            if all(((x + i, y + j) in lit) == pair[j][i] for j in range(16) for i in range(16)):
                found.append((x, y))
    cover = {(x + i, y + j) for x, y in found for j in range(16) for i in range(16) if pair[j][i]}
    assert found and cover == lit, f'{png}: its colour-{c} pixels are not all whole pairs of enemy {e}'
    x0 = min(x for x, _ in found)
    y0 = min(y for _, y in found)
    for line in range(y0, y0 + 64):
        n = sum(1 for _, y in found if y <= line < y + 16)
        assert n <= 4, f'{png}: {n} pairs on line {line}'
    print(f'; {png}: pairs of enemy {e} at {found}')
    print(f'FORM_PAIRS_N    equ {len(found)}')
    print(f'FORM_X0         equ {x0}')
    print(f'FORM_W          equ {max(x for x, _ in found) + 16 - x0}')
    print(f'FORM_H          equ {max(y for _, y in found) + 16 - y0}')
    print('FORM_PAIRS:')
    print('        db ' + ', '.join(f'{x - x0},{y - y0}' for x, y in sorted(found, key=lambda p: (p[1], p[0]))))
    # The boss: four sprites; its booms: BOSS_BOOMS ship booms side by side
    boss, _ = load(BOSS_PNG, 16, 64)
    assert all(any(boss[y]) for y in range(16)) and all(any(boss[y][x] for y in range(16)) for x in (0, 63)), \
        f'{BOSS_PNG}: its art must fill its 64x16 box'
    print('BOSS_W          equ 64')
    print('BOSS_H          equ 16')
    print('BOSS_PATTERN:')
    for k in range(4):
        print_pattern(f'; {BOSS_PNG}, columns {16*k}..{16*k+15}', sprite_pattern([row[16*k:16*k + 16] for row in boss]))
    xs = [round(i * (64 - boom_w) / (BOSS_BOOMS - 1)) for i in range(BOSS_BOOMS)]
    print(f'; the boss booms: {BOSS_BOOMS} at columns {xs}')
    print('BOSS_BOOM_PATTERN:')
    for png in BOOM_PNGS:
        on, _ = load(png, 16, boom_w)
        big = [[any(0 <= x - x0 < boom_w and on[y][x - x0] for x0 in xs) for x in range(64)] for y in range(16)]
        for k in range(4):
            print_pattern(f'; {png} x {BOSS_BOOMS}, columns {16*k}..{16*k+15}', sprite_pattern([row[16*k:16*k + 16] for row in big]))
    # Boss2: in the bitmap (two rows of 8 cells), white and one body colour
    # (set in main.asm: its pattern's fg nibble 0 marks it)
    im = Image.open(BOSS2_PNG).convert('RGB')
    assert im.size == (64, 16), f'{BOSS2_PNG}: {im.size}, want 64x16'
    px = [[im.getpixel((x, y)) for x in range(64)] for y in range(16)]
    on2 = [[p != (0, 0, 0) for p in row] for row in px]
    assert all(any(on2[y]) for y in (0, 15)) and all(any(on2[y][x] for y in range(16)) for x in (0, 63)), \
        f'{BOSS2_PNG}: its art must fill its 64x16 box'
    colours = {nearest(p) for row in px for p in row if p != (0, 0, 0)}
    assert len(colours) == 2 and 15 in colours, f'{BOSS2_PNG}: want white and one body colour, have {colours}'
    pat, col = [], []
    for cy in range(2):
        for cx in range(8):
            for line in range(8):
                y = cy * 8 + line
                byte = px[y][cx * 8:cx * 8 + 8]
                lit = {nearest(p) for p in byte if p != (0, 0, 0)}
                assert len(lit) <= 1, f'{BOSS2_PNG}: line {y}, columns {cx*8}..{cx*8+7}: more than two colours'
                pat.append(sum(0x80 >> i for i in range(8) if byte[i] != (0, 0, 0)))
                col.append(0xF1 if not lit or lit == {15} else 0x01)
    print(f'; {BOSS2_PNG}: the bitmap, its cell rows 0 and 1, 8 cells each')
    print('BOSS2_PAT:')
    for i in range(0, 128, 16):
        print('        db ' + ','.join(f'{b:#04x}' for b in pat[i:i + 16]))
    print('BOSS2_COL:       ; (01h: the body colour, set in main.asm, on black)')
    for i in range(0, 128, 16):
        print('        db ' + ','.join(f'{b:#04x}' for b in col[i:i + 16]))
    print('BOSS2_PATTERN:   ; (as BOSS_PATTERN: its art, for the hits)')
    for k in range(4):
        print_pattern(f'; {BOSS2_PNG}, columns {16*k}..{16*k+15}', sprite_pattern([row[16*k:16*k + 16] for row in on2]))
    print(f'BOSS2_LAST      equ {max(y for y in range(16) if any(on2[y]))}   ; its art\'s last row')
    print('ENEMY_COLS:      ; per enemy, its art\'s first and last columns')
    print('        db ' + ', '.join(f'{l},{r}' for l, r in ecols))
    print('SHIP_ROWS:')
    for i in range(0, 16, 8):
        print('        dw ' + ','.join(f'{w:#06x}' for w in ship_rows[i:i + 8]))


if __name__ == '__main__':
    sys.exit(main())
