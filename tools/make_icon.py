#!/usr/bin/env python3
"""Draws assets/icon.png (the toolbar icon) with the standard library only.

It matches the logo in the plugin window: a cyan-to-violet rounded square
with a white "touch point" (a ring around a dot).
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

SIZE = 128
SAMPLES = 4  # supersampling per axis, for smooth edges
OUTPUT = Path(__file__).resolve().parent.parent / "assets" / "icon.png"

ACCENT = (0, 198, 255)
ACCENT_ALT = (132, 92, 255)
WHITE = (255, 255, 255)

CORNER = 0.24  # corner radius, relative to the icon size
RING_RADIUS = 0.27
RING_WIDTH = 0.065
DOT_RADIUS = 0.105


def inside_rounded_square(x: float, y: float) -> bool:
    # Distance to the inner rectangle the rounded corners are built around.
    dx = max(abs(x - 0.5) - (0.5 - CORNER), 0.0)
    dy = max(abs(y - 0.5) - (0.5 - CORNER), 0.0)
    return dx * dx + dy * dy <= CORNER * CORNER


def sample(x: float, y: float) -> tuple[float, float, float, float]:
    if not inside_rounded_square(x, y):
        return (0.0, 0.0, 0.0, 0.0)

    distance = math.hypot(x - 0.5, y - 0.5)
    if distance <= DOT_RADIUS or abs(distance - RING_RADIUS) <= RING_WIDTH / 2:
        return (*WHITE, 255.0)

    t = (x + y) / 2  # diagonal gradient
    color = tuple(a + (b - a) * t for a, b in zip(ACCENT, ACCENT_ALT))
    return (*color, 255.0)


def render() -> bytes:
    rows = []
    for py in range(SIZE):
        row = bytearray([0])  # PNG filter type: none
        for px in range(SIZE):
            total = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = (px + (sx + 0.5) / SAMPLES) / SIZE
                    y = (py + (sy + 0.5) / SAMPLES) / SIZE
                    r, g, b, a = sample(x, y)
                    # Premultiply so edge pixels blend correctly.
                    total[0] += r * a
                    total[1] += g * a
                    total[2] += b * a
                    total[3] += a
            alpha = total[3] / (SAMPLES * SAMPLES)
            if total[3] > 0:
                rgb = [round(channel / total[3]) for channel in total[:3]]
            else:
                rgb = [0, 0, 0]
            row.extend([*rgb, round(alpha)])
        rows.append(bytes(row))
    return b"".join(rows)


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def main() -> None:
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)  # 8-bit RGBA
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(render(), 9)) + chunk(b"IEND", b"")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(png)
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
