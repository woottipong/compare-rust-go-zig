#!/usr/bin/env python3
"""Generate a parquet-subset binary for RLE/bit-pack decoding benchmark."""
import json
import struct
from pathlib import Path

BIT_WIDTH = 6
NUM_VALUES = 200_000

root = Path(__file__).resolve().parent
out = root / "sample.parquet"

values = []
for i in range(NUM_VALUES):
    if i % 50 < 20:
        values.append(7)
    else:
        values.append((i * 13) % (1 << BIT_WIDTH))


def encode_varint(v: int) -> bytes:
    outb = bytearray()
    while True:
        b = v & 0x7F
        v >>= 7
        if v:
            outb.append(b | 0x80)
        else:
            outb.append(b)
            break
    return bytes(outb)


def encode_hybrid(nums):
    payload = bytearray()
    i = 0
    while i < len(nums):
        run = 1
        while i + run < len(nums) and nums[i + run] == nums[i] and run < 0x3FFF:
            run += 1
        if run >= 8:
            payload += encode_varint(run << 1)
            payload += struct.pack("<B", nums[i])
            i += run
            continue

        chunk = nums[i : min(i + 8, len(nums))]
        while len(chunk) < 8:
            chunk.append(0)
        payload += encode_varint((1 << 1) | 1)

        bitbuf = 0
        bitcount = 0
        packed = bytearray()
        for v in chunk:
            bitbuf |= (v & ((1 << BIT_WIDTH) - 1)) << bitcount
            bitcount += BIT_WIDTH
            while bitcount >= 8:
                packed.append(bitbuf & 0xFF)
                bitbuf >>= 8
                bitcount -= 8
        if bitcount:
            packed.append(bitbuf & 0xFF)
        payload += packed
        i += 8
    return bytes(payload)

encoded = encode_hybrid(values)
metadata = json.dumps(
    {
        "rows": NUM_VALUES,
        "encoding": "RLE_BITPACK_HYBRID",
        "bit_width": BIT_WIDTH,
    },
    separators=(",", ":"),
).encode("utf-8")

body = bytearray()
body += b"PAR1"
body += struct.pack("<BII", BIT_WIDTH, NUM_VALUES, len(encoded))
body += encoded
body += metadata
body += struct.pack("<I", len(metadata))
body += b"PAR1"

out.write_bytes(body)
size_mb = out.stat().st_size / (1024 * 1024)
print(f"Generated {out}")
print(f"Rows: {NUM_VALUES:,}")
print(f"Encoded size: {len(encoded):,} bytes")
print(f"File size: {size_mb:.2f} MB")
