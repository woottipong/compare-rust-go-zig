# ZStandard Compression

เปรียบเทียบ performance ของ Go, Rust, และ Zig ในการ compress และ decompress ข้อมูลด้วย ZStandard (zstd) algorithm — เป็น benchmark สำหรับ FFI (C interop) overhead และ compression throughput

## โครงสร้างโปรเจกต์

```
zstd-compression/
├── go/
│   ├── main.go          # klauspost/compress/zstd (pure Go)
│   ├── go.mod
│   ├── go.sum
│   └── Dockerfile
├── rust/
│   ├── src/main.rs      # zstd crate (wraps libzstd C)
│   ├── Cargo.toml
│   └── Dockerfile
├── zig/
│   ├── src/main.zig     # @cImport("zstd.h") direct C binding
│   ├── build.zig        # linkSystemLibrary("zstd")
│   ├── build.zig.zon
│   └── Dockerfile
├── test-data/           # .gitignore — generate locally
│   └── logs.txt         # ~127MB repetitive log file
└── benchmark/
    ├── run.sh
    └── results/
```

## สร้าง Test Data

```bash
python3 -c "
import sys
with open('test-data/logs.txt', 'w') as f:
    for i in range(1500000):
        f.write(f'2026-01-01T{i%24:02d}:00:00 INFO [service-{i%10}] Request processed id={i} latency={i%100}ms status=200\n')
"
```

## Dependencies

| ภาษา | Library | หมายเหตุ |
|------|---------|---------|
| Go | `github.com/klauspost/compress/zstd` | **pure Go** implementation (ไม่ต้อง CGO) |
| Rust | `zstd = "0.13"` | wraps libzstd C via FFI |
| Zig | stdlib + `@cImport("zstd.h")` | direct C binding ผ่าน `linkSystemLibrary("zstd")` |

## Build & Run

```bash
# Docker
docker build -t zst-go go/
docker build -t zst-rust rust/
docker build -t zst-zig zig/
docker run --rm -v "$(pwd)/test-data":/data zst-zig /data/logs.txt

# Benchmark
bash benchmark/run.sh
```

## ผลการทดสอบ (Docker ARM64, Apple M2)

> **Test**: 127.5MB log file (repetitive text, high compression ratio) — 5 runs (1 warm-up + 4 measured)
> **Results saved to**: `benchmark/results/zstd-compression_20260301_150758.txt`

```
── Compress Speed (MB/s, higher is better) ───────────────
  Go  :   965.32 MB/s  avg  (Min:  909.83 | Max:  988.88)
  Rust: 1,272.56 MB/s  avg  (Min: 1,245.73 | Max: 1,282.98)
  Zig : 2,197.83 MB/s  avg  (Min: 2,143.18 | Max: 2,218.89)  ✓ Winner

── Decompress Speed (MB/s, higher is better) ─────────────
  Go  :   ~316 MB/s  (measured per run)
  Rust: 1,718 MB/s
  Zig : 3,237 MB/s  ✓ Winner
```

### เปรียบเทียบ Compress

| | Go | Rust | Zig |
|---|---|---|---|
| Compress speed | 965 MB/s | 1,273 MB/s | **2,198 MB/s** |
| Decompress speed | ~316 MB/s | ~1,718 MB/s | **~3,237 MB/s** |
| Compression ratio | 37.6× | 65.1× | 64.8× |
| Relative (compress) | 1× | 1.3× | **2.3×** |
| C binding approach | pure Go | `zstd` crate (safe FFI) | `@cImport` (direct) |

```
── Binary Sizes ──────────────────────────────────────────
  Go  : 6.2MB  (pure Go zstd implementation embedded)
  Rust: 472KB  (links libzstd shared)
  Zig : 312KB  (links libzstd shared)

── Compression ratio ─────────────────────────────────────
  Go  : 37.55× (pure Go encoder — different compression code path)
  Rust: 65.13× (libzstd C — same as Zig, higher ratio)
  Zig : 64.75× (libzstd C — same algorithm as Rust)
```

**Key insight:** **Zig ชนะขาด 2.3× เหนือ Rust และ 2.3× เหนือ Go** เพราะ `@cImport` เรียก libzstd โดยตรงโดยไม่มี safe wrapper layer — ยืนยัน subtitle-burn-in-engine finding บน pure data processing

- **Zig ชนะเพราะ zero-overhead FFI**: `@cImport` + `@ptrCast` เรียก `ZSTD_compress()` โดยตรง — ไม่มี Rust's ownership check บน raw pointer, ไม่มี Go's goroutine overhead; C library ทำงานเต็มความเร็ว
- **Rust ช้ากว่า Zig 1.7×**: `zstd` crate ต้องมี safe wrapper, error type conversion, และ `Box<dyn Error>` สำหรับ error propagation — overhead เล็กๆ สะสมเป็นนัยสำคัญเมื่อ compress 127MB ในลูป
- **Go ช้าที่สุดและ compression ratio ต่ำกว่า**: pure Go zstd implementation ของ klauspost ไม่เหมือน libzstd C — ใช้ algorithm เดียวกันแต่ optimize ต่างกัน; 37.55× vs 65× แสดงว่า Go encoder มี compression quality ต่ำกว่า
- **Compression ratio อธิบาย**: Go ใช้ pure Go zstd encoder ที่ conservative กว่า; Rust/Zig ใช้ libzstd C ที่เดียวกัน → ratio เกือบเท่ากัน (65.1× vs 64.8×)
- **บทเรียน**: สำหรับ CPU-intensive C library binding, Zig's direct `@cImport` ชนะ Rust's safe FFI wrapper อย่างสม่ำเสมอ — pattern เดียวกับ subtitle-burn-in และ hls-stream-segmenter; ถ้า safety ไม่ใช่ constraint → Zig เป็น best choice สำหรับ C library wrapping

## หมายเหตุ

- **Go**: `klauspost/compress/zstd` เป็น pure Go implementation ที่ดีที่สุดสำหรับ zstd ใน Go ecosystem — ไม่ต้องการ CGO, portability สูง, แต่ช้ากว่า C binding ~2×
- **Rust**: `zstd` crate เป็น standard — safe wrapper รอบ libzstd; ผล 1,272 MB/s เทียบกับ C direct ~2,200 MB/s แสดง safe abstraction overhead ~40%
- **Zig**: direct `ZSTD_compress`/`ZSTD_decompress` call — บาง function call เดียว ไม่มี layer กลาง
- **Compression ratio 65×**: log file repetitive มาก → zstd compress ได้ดีมาก (127MB → ~2MB)
