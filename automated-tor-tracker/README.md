# Automated TOR Tracker: Go vs Rust vs Zig

จำลองการประมวลผลไฟล์ TOR (Terms of Reference) บรรทัดต่อบรรทัด เพื่อจัดหมวดสถานะงาน (done/in_progress/blocked/todo) ซ้ำหลายรอบ เพื่อวัด throughput ของ string search + classification ใน short-line input

## โครงสร้าง

```text
automated-tor-tracker/
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
│   └── tor.txt   # 10 TOR tracking entries
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
unset GOROOT && go build -o ../bin/att-go ./go

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

อ้างอิงจาก: `benchmark/results/automated-tor-tracker_20260227_132048.txt`

```
Input   : 10 TOR tracking entries
Repeats : 1,000,000 scan cycles
Total   : 10,000,000 line classifications per language
Checks  : done, completed, in progress, ongoing, blocked, risk
```

| Run | Go | Rust | Zig |
|-----|---:|-----:|----:|
| Warm-up | 1940ms | 1355ms | 415ms |
| Run 2 | 1933ms | 1253ms | 485ms |
| Run 3 | 1983ms | 1287ms | 418ms |
| Run 4 | 1931ms | 1253ms | 418ms |
| Run 5 | 1957ms | 1256ms | 423ms |
| **Avg** | **1,951ms** | **1,262ms** | **436ms** |
| Min | 1,931ms | 1,253ms | 418ms |
| Max | 1,983ms | 1,287ms | 485ms |

### Summary

| Metric | Go | Rust | Zig |
|--------|---:|-----:|----:|
| Avg Time | 1,951ms | 1,262ms | **436ms** |
| Throughput | 5.1M items/s | 7.96M items/s | **23.6M items/s** |
| Binary Size | 1.6MB | **388KB** | 2.2MB |
| Code Lines | 116 | 107 | **98** |

## Key Insight

**Zig ชนะ 3× เหนือ Rust และ 4.5× เหนือ Go — เพราะหลีกเลี่ยง string allocation สำหรับ case conversion บน short input**

`extractStatus()` ใช้ string search ในแต่ละภาษาแตกต่างกัน:

| ภาษา | Lowercase conversion | Search strategy |
|------|---------------------|-----------------:|
| **Zig** | ไม่มี (case-sensitive search) | `std.mem.indexOf` โดยตรง |
| **Rust** | `to_ascii_lowercase()` per line | `contains()` ← LLVM SIMD |
| **Go** | `strings.ToLower()` per line | `strings.Contains()` หลายครั้ง |

- **Zig เร็วสุด**: ข้ามการ lowercase ทั้งหมด → ไม่มี allocation per line → `std.mem.indexOf` วิ่ง native byte-compare → 23.6M lines/sec
- **Rust กลาง**: `to_ascii_lowercase()` ต้อง allocate String ใหม่ทุกบรรทัด สำหรับ input สั้น (~20-50 chars) overhead ของ allocation มากกว่า SIMD gain จาก `contains()` → 7.96M lines/sec
- **Go ช้าสุด**: `strings.ToLower()` allocate String ใหม่ + `strings.Contains()` ไม่ได้รับ SIMD optimization เทียบเท่า Rust → 5.1M lines/sec

pattern ต่างจาก web-accessibility-crawler ที่ Rust ชนะ: เมื่อ input string สั้น (~30 chars/line) SIMD ได้ประโยชน์น้อย แต่ cost ของ `to_ascii_lowercase()` allocation ยังคงสูง — Zig จึงชนะด้วยการหลีกเลี่ยง allocation ทั้งหมด

**Rust binary เล็กสุด 388KB** (vs Go 1.6MB, Zig 2.2MB)
