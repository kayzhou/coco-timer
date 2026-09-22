#!/usr/bin/env python3
"""Draw the sample figure shipped with the Chinese template."""

import struct
import zlib
from pathlib import Path


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def pixel(x, y, width, height):
    rice = (245, 242, 234)
    ink = (25, 24, 44)
    lime = (217, 243, 107)
    white = (255, 255, 255)
    purple = (101, 83, 212)
    if x < 10 or y < 10 or x >= width - 10 or y >= height - 10:
        return ink
    if 36 <= x < 250 and 36 <= y < 168:
        return lime
    if 52 <= x < 266 and 52 <= y < 184:
        return ink
    if 68 <= x < 250 and 68 <= y < 168:
        return white
    bar_x = 320
    for index, bar_h in enumerate((70, 120, 96, 150)):
        left = bar_x + index * 78
        top = height - 48 - bar_h
        if left <= x < left + 46 and top <= y < height - 48:
            return purple if index % 2 == 0 else ink
    if 68 <= x < 250 and 188 <= y < 196:
        return ink
    return rice


def write_png(path, width, height):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(pixel(x, y, width, height))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    Path(path).write_bytes(png)


if __name__ == "__main__":
    target = Path(__file__).resolve().parents[1] / "templates" / "article" / "figure.png"
    write_png(target, 720, 280)
