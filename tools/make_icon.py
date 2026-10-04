#!/usr/bin/env python3
"""Draws assets/icon.png (the toolbar icon) with the standard library only.

It matches the logo in the plugin window: two peaks on graphite, the front
one bone white with a green light on its summit.
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

SIZE = 128
SAMPLES = 4  # supersampling per axis, for smooth edges
OUTPUT = Path(__file__).resolve().parent.parent / "assets" / "icon.png"

GRAPHITE = (35, 37, 39)
BONE = (236, 232, 223)
DIM = (96, 95, 91)
GREEN = (92, 201, 122)

CORNER = 0.22  # corner radius, relative to the icon size
STROKE = 0.055  # line width of the peaks


def inside_rounded_square(x: float, y: float) -> bool:
    dx = max(abs(x - 0.5) - (0.5 - CORNER), 0.0)
    dy = max(abs(y - 0.5) - (0.5 - CORNER), 0.0)
    return dx * dx + dy * dy <= CORNER * CORNER


def near_segment(x: float, y: float, a: tuple[float, float], b: tuple[float, float], width: float) -> bool:
    ax, ay = a
    bx, by = b
    vx, vy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy)))
    px, py = ax + vx * t, ay + vy * t
    return math.hypot(x - px, y - py) <= width / 2


def peak(apex: tuple[float, float], length: float) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    dx, dy = length * math.cos(math.radians(60)), length * math.sin(math.radians(60))
    ax, ay = apex
    return [((ax - dx, ay + dy), apex), (apex, (ax + dx, ay + dy))]


FRONT = peak((0.42, 0.36), 0.40)
BACK = peak((0.66, 0.52), 0.24)
SUMMIT = (0.42, 0.25)


def sample(x: float, y: float) -> tuple[float, float, float, float]:
    if not inside_rounded_square(x, y):
        return (0.0, 0.0, 0.0, 0.0)
    if math.hypot(x - SUMMIT[0], y - SUMMIT[1]) <= 0.055:
        return (*GREEN, 255.0)
    if any(near_segment(x, y, a, b, STROKE) for a, b in FRONT):
        return (*BONE, 255.0)
    if any(near_segment(x, y, a, b, STROKE) for a, b in BACK):
        return (*DIM, 255.0)
    return (*GRAPHITE, 255.0)


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
            rgb = [round(channel / total[3]) for channel in total[:3]] if total[3] > 0 else [0, 0, 0]
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
