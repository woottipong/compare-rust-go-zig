#!/usr/bin/env python3
"""Generate sample PPM image for PNG encoder benchmark."""
from pathlib import Path

WIDTH = 512
HEIGHT = 512

root = Path(__file__).resolve().parent
output = root / "sample.ppm"

header = f"P6\n{WIDTH} {HEIGHT}\n255\n".encode("ascii")

pixels = bytearray()
for y in range(HEIGHT):
    for x in range(WIDTH):
        r = (x * 255) // (WIDTH - 1)
        g = (y * 255) // (HEIGHT - 1)
        b = ((x + y) * 255) // (WIDTH + HEIGHT - 2)
        pixels.extend((r, g, b))

output.write_bytes(header + pixels)
size_mb = output.stat().st_size / (1024 * 1024)
print(f"Generated {output}")
print(f"Dimensions: {WIDTH}x{HEIGHT}")
print(f"Size: {size_mb:.2f} MB")
