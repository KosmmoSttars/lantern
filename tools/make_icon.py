"""The game's icon: a lantern in the title's chunky amber pixels on a dark, starry square.

Drawn on a 32 x 32 grid and blown up without smoothing. Writes icon.png (256 px, the window
icon, set in project.godot) and tools/icon.ico (16 to 256 px, for the executable).

    python tools/make_icon.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
N = 32
BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

BG = (12, 14, 22)
BG2 = (20, 23, 36)
EDGE = (6, 6, 9)
METAL = (58, 54, 52)
METAL_HI = (104, 96, 88)
AMBER = [(255, 236, 170), (255, 205, 105), (246, 156, 62), (200, 104, 36)]
GLOW = (120, 70, 26)


def bayer(x, y):
    return (BAYER[(y % 4) * 4 + x % 4] + 0.5) / 16.0


def draw():
    px = [[BG for _ in range(N)] for _ in range(N)]
    # A soft lift toward the middle, and a few stars.
    for y in range(N):
        for x in range(N):
            d = ((x - 15.5) ** 2 + (y - 16.5) ** 2) ** 0.5 / 16.0
            if 1.0 - d > bayer(x, y) * 1.4:
                px[y][x] = BG2
    for x, y in [(4, 4), (27, 6), (6, 25), (26, 27), (24, 13), (5, 15), (12, 2)]:
        px[y][x] = (200, 205, 225)
    # The warm halo round the glass.
    for y in range(N):
        for x in range(N):
            d = ((x - 15.5) ** 2 / 1.2 + (y - 17) ** 2) ** 0.5
            if d < 10.5 and (10.5 - d) / 10.5 > bayer(x, y) * 0.9 + 0.25:
                px[y][x] = GLOW
    # Handle.
    for x in range(12, 20):
        px[3][x] = METAL
    for y in range(4, 7):
        px[y][11] = METAL
        px[y][20] = METAL
    # Cap: a trapezoid of dark metal with a lit rim.
    for y, (a, b) in zip(range(7, 10), [(13, 18), (11, 20), (10, 21)]):
        for x in range(a, b + 1):
            px[y][x] = METAL_HI if y == 7 else METAL
    # Glass: the frame and the light inside, brightest at the flame.
    for y in range(10, 23):
        for x in range(10, 22):
            frame = x in (10, 21) or x == 15 and y in (10, 22)
            if frame:
                px[y][x] = METAL
                continue
            d = ((x - 15.5) ** 2 + ((y - 17.5) * 0.8) ** 2) ** 0.5 / 6.0
            t = min(max(d, 0.0), 1.0) * (len(AMBER) - 1)
            k = min(int(t + (1 if t - int(t) > bayer(x, y) else 0)), len(AMBER) - 1)
            px[y][x] = AMBER[k]
    for y in range(15, 20):
        px[y][15] = (255, 252, 230)
        px[y][16] = (255, 252, 230)
    px[14][15] = (255, 240, 190)
    # Base.
    for y, (a, b) in zip(range(23, 26), [(10, 21), (9, 22), (11, 20)]):
        for x in range(a, b + 1):
            px[y][x] = METAL_HI if y == 23 else METAL
    # A dark outline round the lantern.
    shape = {(x, y) for y in range(3, 26) for x in range(9, 23) if px[y][x] in (METAL, METAL_HI) or 10 <= y <= 22 and 10 <= x <= 21}
    for y in range(N):
        for x in range(N):
            if (x, y) in shape:
                continue
            if any((x + dx, y + dy) in shape for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                if px[y][x] not in (METAL,):
                    px[y][x] = EDGE
    img = Image.new("RGB", (N, N))
    for y in range(N):
        for x in range(N):
            img.putpixel((x, y), px[y][x])
    return img


def main():
    small = draw()
    big = small.resize((256, 256), Image.NEAREST)
    big.save(ROOT / "icon.png")
    big.save(ROOT / "tools" / "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("icon.png, tools/icon.ico")


if __name__ == "__main__":
    main()
