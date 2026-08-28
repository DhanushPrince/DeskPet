#!/usr/bin/env python3
"""Draw the menu-bar paw at 1024×1024 into docs/app-icon.png."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

SIZE = 1024
SCALE = SIZE / 22.0
# TrayIcon.swift source circles, y-down like the original buffer.
CIRCLES = [
    (5, 4, 2.4),
    (11, 2.5, 2.4),
    (17, 4, 2.4),
    (3, 9, 2.4),
    (11, 15, 7),
]
BACKGROUND = (250, 246, 238, 255)
PAW = (59, 48, 37, 255)


def png_rgba(pixels: bytearray, width: int, height: int) -> bytes:
    raw = bytearray()
    row = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * row : (y + 1) * row])

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(
            ">I", zlib.crc32(tag + data) & 0xFFFFFFFF
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            chunk(b"IHDR", header),
            chunk(b"IDAT", zlib.compress(bytes(raw), 9)),
            chunk(b"IEND", b""),
        ]
    )


def main() -> None:
    pixels = bytearray(bytes(BACKGROUND) * SIZE * SIZE)
    for x, y, radius in CIRCLES:
        cx = x * SCALE
        cy = y * SCALE
        r = radius * SCALE
        r2 = r * r
        x0 = max(0, int(cx - r) - 1)
        x1 = min(SIZE, int(cx + r) + 2)
        y0 = max(0, int(cy - r) - 1)
        y1 = min(SIZE, int(cy + r) + 2)
        for py in range(y0, y1):
            for px in range(x0, x1):
                dx = px + 0.5 - cx
                dy = py + 0.5 - cy
                if dx * dx + dy * dy <= r2:
                    i = (py * SIZE + px) * 4
                    pixels[i : i + 4] = bytes(PAW)

    out = Path(__file__).resolve().parents[1] / "docs" / "app-icon.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png_rgba(pixels, SIZE, SIZE))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
