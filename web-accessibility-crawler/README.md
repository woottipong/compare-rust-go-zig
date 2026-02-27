# Web Accessibility Crawler: Go vs Rust vs Zig

จำลองการ scan หน้าเว็บ HTML เพื่อหาปัญหา accessibility (missing lang/title, img ไม่มี alt, link ไม่มี aria-label) ซ้ำหลายรอบ เพื่อวัด throughput ของ string search ใน HTML

## โครงสร้าง

```text
web-accessibility-crawler/
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
│   └── pages.html   # 5 HTML pages แบ่งด้วย "===\n"
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies

- Docker (for benchmark)

## Build

```bash
# Go
unset GOROOT && go build -o ../bin/wac-go ./go

# Rust
cargo build --release --manifest-path rust/Cargo.toml

# Zig
cd zig && zig build -Doptimize=ReleaseFast
```

## Run Benchmark

```bash
bash benchmark/run.sh
# Results saved to benchmark/results/
```

## Benchmark Results

อ้างอิงจาก: `benchmark/results/web-accessibility-crawler_20260227_131524.txt`

```
Input   : 5 HTML pages (467 bytes total)
Repeats : 700,000 scan cycles
Total   : 3,500,000 page scans per language
Checks  : lang attr, title, img alt, aria-label
```

| Run | Go | Rust | Zig |
|-----|---:|-----:|----:|
| Warm-up | 2862ms | 791ms | 896ms |
| Run 2 | 2547ms | 790ms | 922ms |
| Run 3 | 2684ms | 796ms | 973ms |
| Run 4 | 2672ms | 807ms | 893ms |
| Run 5 | 2533ms | 792ms | 900ms |
| **Avg** | **2,609ms** | **796ms** | **922ms** |
| Min | 2,533ms | 790ms | 893ms |
| Max | 2,684ms | 807ms | 973ms |

### Summary

| Metric | Go | Rust | Zig |
|--------|---:|-----:|----:|
| Avg Time | 2,609ms | **796ms** | 922ms |
| Throughput | 1.38M items/s | **4.42M items/s** | 3.89M items/s |
| Binary Size | 1.7MB | **388KB** | 2.2MB |
| Code Lines | 117 | **108** | 114 |

## Key Insight

**Rust ชนะ 3.3× เหนือ Go และ 1.2× เหนือ Zig — เพราะ lowercase conversion strategy**

`countIssues()` ใช้ string search ในแต่ละภาษาแตกต่างกัน:

| ภาษา | Lowercase conversion | Search strategy |
|------|---------------------|-----------------|
| **Rust** | `to_ascii_lowercase()` ครั้งเดียว | `contains()` + `matches()` ← LLVM SIMD |
| **Zig** | ไม่มี (case-sensitive search) | `indexOf` loop หลายรอบ |
| **Go** | `strings.ToLower()` ครั้งเดียว | `strings.Contains()` + `strings.Count()` |

- **Rust เร็วสุด**: `to_ascii_lowercase()` ใช้ SIMD pass เดียว + `contains()`/`matches()` ที่ LLVM optimize เป็น SIMD substring search → throughput 4.4M pages/sec
- **Zig ตรงกลาง**: ข้ามการ lowercase (case-sensitive) ประหยัด 1 pass แต่ `std.mem.indexOf` ใช้ naive byte-by-byte search ไม่ SIMD → 3.9M pages/sec
- **Go ช้าสุด**: `strings.ToLower` + `strings.Contains`/`strings.Count` ไม่ได้รับ SIMD optimization แบบเดียวกับ Rust → 1.4M pages/sec (3× ช้ากว่า Rust)

Rust variance ต่ำมาก (790-807ms = 2%) แสดงว่า workload นี้ CPU-bound ล้วนๆ ไม่มี I/O noise

**Rust binary เล็กสุด 388KB** (vs Go 1.7MB, Zig 2.2MB)
