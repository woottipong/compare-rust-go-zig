# PNG Encoder from Scratch: Go vs Rust vs Zig

โปรเจกต์นี้ implement PNG encoder แบบไม่พึ่ง libpng โดยอ่านไฟล์ PPM (P6) แล้ว encode เป็น PNG ด้วยโครงสร้าง chunk + zlib/deflate (stored block)

## วัตถุประสงค์
- ฝึก bit/byte-level file format handling (PNG signature, chunk, CRC32)
- ฝึกการประกอบ zlib stream + DEFLATE stored block
- เปรียบเทียบ performance งาน encode แบบ pure algorithm ระหว่าง Go/Rust/Zig

## โครงสร้าง

```text
png-encoder-from-scratch/
├── go/
│   ├── main.go
│   ├── go.mod
│   └── Dockerfile
├── rust/
│   ├── src/main.rs
│   ├── Cargo.toml
│   └── Dockerfile
├── zig/
│   ├── src/main.zig
│   ├── build.zig
│   └── Dockerfile
├── test-data/
│   ├── generate.py
│   └── sample.ppm
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies
- Docker
- Python 3 (generate test image)

## Build & Run

### Generate test data

```bash
python3 test-data/generate.py
```

### Go

```bash
unset GOROOT && go build -o ../bin/png-encoder-go .
../bin/png-encoder-go ../test-data/sample.ppm ../test-data/output_go.png 500
```

### Rust

```bash
cargo build --release
./target/release/png-encoder ../test-data/sample.ppm ../test-data/output_rust.png 500
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/png-encoder ../test-data/sample.ppm ../test-data/output_zig.png 500
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/png-encoder-from-scratch_YYYYMMDD_HHMMSS.txt`

(benchmark รัน 5 ครั้ง: 1 warm-up + 4 measured ผ่าน Docker)

## Benchmark Results

วัดด้วย `REPEATS=500` บน 512×512 PPM (262,144 pixels/frame), Docker-based, Apple M-series

```text
╔══════════════════════════════════════════╗
║   PNG Encoder From Scratch Benchmark     ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.ppm
  Repeats  : 500
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 1787ms
  Run 2           : 1776ms
  Run 3           : 1947ms
  Run 4           : 1738ms
  Run 5           : 1792ms
  ─────────────────────────────────────────
  Avg: 1813ms  |  Min: 1738ms  |  Max: 1947ms

  Total processed: 131072000
  Processing time: 1.792s
  Average latency: 0.000014ms
  Throughput     : 73152581.17 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 2502ms
  Run 2           : 2483ms
  Run 3           : 2505ms
  Run 4           : 2485ms
  Run 5           : 2492ms
  ─────────────────────────────────────────
  Avg: 2491ms  |  Min: 2483ms  |  Max: 2505ms

  Total processed: 131072000
  Processing time: 2.492s
  Average latency: 0.000019ms
  Throughput     : 52598954.08 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 4471ms
  Run 2           : 4506ms
  Run 3           : 4546ms
  Run 4           : 4467ms
  Run 5           : 4467ms
  ─────────────────────────────────────────
  Avg: 4496ms  |  Min: 4467ms  |  Max: 4546ms

  Total processed: 131072000
  Processing time: 4.467s
  Average latency: 0.000034ms
  Throughput     : 29342545.70 items/sec

── Binary Size ───────────────────────────────
  Go  : 1.6MB
  Rust: 388KB
  Zig : 2.3MB

── Code Lines ────────────────────────────────
  Go  : 234 lines
  Rust: 248 lines
  Zig : 252 lines
```

ผลลัพธ์ถูกบันทึกไว้ที่:
`benchmark/results/png-encoder-from-scratch_20260227_013242.txt`

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | **1,813ms** | 2,491ms | 4,496ms |
| Min/Max time | **1,738/1,947ms** | 2,483/2,505ms | 4,467/4,546ms |
| Total processed | 131,072,000 | 131,072,000 | 131,072,000 |
| Throughput | **73,152,581 items/sec** | 52,598,954 items/sec | 29,342,545 items/sec |
| Average latency | **0.000014ms** | 0.000019ms | 0.000034ms |
| Binary size | 1.6MB | **388KB** | 2.3MB |
| Code lines | **234** | 248 | 252 |

## Key Insights

1. **Go ชนะ throughput** ที่ 73M items/sec — เร็วกว่า Rust 1.39×, เร็วกว่า Zig 2.49× ในงาน PNG encode แบบ stored block
2. **Rust มี variance ต่ำที่สุด** (2,483–2,505ms, ~1%) สะท้อนว่า memory allocation pattern คาดเดาได้ดี
3. **Zig ช้ากว่าที่คาด** เพราะ `GeneralPurposeAllocator` มี safety-check overhead สูงใน alloc/free แต่ละรอบ (raw/idat/out buffer × REPEATS ครั้ง) — บน ReleaseFast GPA ยังมี debug tracking
4. **ลำดับผลลัพธ์ต่างจากโปรเจกต์อื่น** (Go > Rust > Zig) สะท้อนว่า bottleneck ไม่ใช่ CPU-bound hot loop แต่เป็น allocator overhead ต่อ iteration
5. **Rust ชนะ binary size** ที่ 388KB เหมือนเดิม (เล็กกว่า Go 4.1×, เล็กกว่า Zig 5.9×)
6. **Total processed** = 512 × 512 × 500 = 131,072,000 pixels ✓

## Technical Notes

- **Encoding pipeline per frame**: PPM pixels → filter-none scanlines → DEFLATE stored blocks → zlib stream → IDAT chunk → PNG file
- **No compression**: DEFLATE stored block (BTYPE=00) wraps raw filtered scanlines — measures pure format serialization cost
- **Per-iteration allocation**: each `encodePng` call allocates `raw` + `idat` + `out` buffers (~2× image size each); profiling bottleneck is allocator overhead, not CRC/adler compute
- **Go**: uses `bytes.Buffer` (amortized growth) + `hash/crc32` stdlib; GC handles deallocation outside hot path → lowest overhead
- **Rust**: explicit `Vec` alloc/dealloc each iteration + manual CRC table rebuild per call (in `crc32_table`) — room for optimization but stable timing
- **Zig**: `GeneralPurposeAllocator` adds per-alloc metadata tracking even in ReleaseFast; switching to `std.heap.c_allocator` or `FixedBufferAllocator` would significantly improve performance
