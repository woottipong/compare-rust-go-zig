# Container Watchdog

จำลอง agent ที่คอย poll metrics ของ container แล้วตัดสินใจ trigger action ตาม policy เพื่อเปรียบเทียบ throughput ของ Go / Rust / Zig ในงาน sidecar event-loop

## วัตถุประสงค์

- **Event-loop throughput**: วัดความเร็วในการอ่าน sample → ตัดสินใจ policy → ลงมือ action
- **Policy engine**: streak detection + cooldown ป้องกัน action ถี่เกินไป
- **Sidecar pattern**: binary เล็ก, memory ต่ำ, รัน parallel กับ main process

## ทักษะที่ฝึก

- **Go**: range loop over slice, integer counters, branching
- **Rust**: slice iteration, `saturating_sub`, const generics
- **Zig**: for-each loop บน slice, comptime constants, no GC

## Directory Structure

```text
container-watchdog/
├── go/
│   ├── main.go         # CSV loader + policy loop
│   ├── go.mod
│   └── Dockerfile
├── rust/
│   ├── src/main.rs     # CSV loader + policy loop
│   ├── Cargo.toml      # ไม่มี external dependencies
│   └── Dockerfile
├── zig/
│   ├── src/main.zig    # CSV loader + policy loop
│   ├── build.zig       # Zig 0.15+ build system
│   ├── build.zig.zon
│   └── Dockerfile
├── test-data/
│   └── metrics.csv     # 5,000 samples: idx,cpu%,mem%
├── benchmark/
│   └── run.sh
└── README.md
```

## Policy Algorithm

```
thresholds: CPU > 85%, MEM > 90%
streak_limit: 3 consecutive samples
cooldown: 20 ticks หลัง trigger

ทุก sample:
  1. decrement cooldown (if active)
  2. update cpu_streak / mem_streak
  3. if mem_streak ≥ 3 AND cooldown == 0 → trigger action, reset streaks, set cooldown=20
  4. elif cpu_streak ≥ 3 → trigger action, reset cpu_streak
```

**ลำดับ priority**: MEM ก่อน CPU — mem-triggered action reset ทั้ง 2 streaks และ cooldown ป้องกัน action ซ้ำ; CPU-triggered action ไม่มี cooldown (เหมาะกับ CPU spike ที่ควรตอบสนองทุกครั้ง)

## Test Data (test-data/metrics.csv)

5,000 rows, format `idx,cpu%,mem%`:

```csv
0,55.58,40.88
1,41.00,47.81
...
4999,63.25,91.58
```

- CPU range: ~25–99%
- MEM range: ~35–99%
- ออกแบบให้มี streak ของ CPU>85% และ MEM>90% กระจายทั่วไฟล์

## Dependencies

### macOS
- Go 1.25+, Rust 1.85+, Zig 0.15.2+, Docker Desktop

### Linux (Docker)
- `golang:1.25-bookworm`, `rust:1.85-bookworm`, `debian:bookworm-slim` (Zig)

## Build & Run

### Local

```bash
# Go
cd go && unset GOROOT && go build -o ../bin/wd-go .

# Rust
cd rust && cargo build --release

# Zig
cd zig && zig build -Doptimize=ReleaseFast
```

### Docker

```bash
docker build -t wd-go go/
docker build -t wd-rust rust/
docker build -t wd-zig zig/
```

### Run

```bash
# Default: metrics.csv, 150,000 loops
docker run --rm -v "$PWD/test-data:/data:ro" wd-go
docker run --rm -v "$PWD/test-data:/data:ro" wd-rust
docker run --rm -v "$PWD/test-data:/data:ro" wd-zig

# Custom loops
docker run --rm -v "$PWD/test-data:/data:ro" wd-go /data/metrics.csv 50000
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์ auto-save ลง `benchmark/results/container_watchdog_<timestamp>.txt`

รัน 5 ครั้ง: 1 warm-up + 4 measured แสดง Avg/Min/Max throughput และ binary size

## ผลการวัด (Benchmark Results)

วัดด้วย 150,000 loops บน 5,000 samples = **750M items/run**,
Docker-based, Apple M-series

```
╔════════════════════════════╗
║ Container Watchdog Bench   ║
╚════════════════════════════╝

─ Go ─────────────────────
  Warm-up: 760396481.17 items/sec
  Run 1: 679529908.22 items/sec
  Run 2: 736892255.51 items/sec
  Run 3: 730069743.64 items/sec
  Run 4: 649711611.24 items/sec
  Avg: 699050879.65 items/sec
  Min: 649711611 items/sec
  Max: 736892256 items/sec

─ Rust ─────────────────────
  Warm-up: 776827032.44 items/sec
  Run 1: 741134336.04 items/sec
  Run 2: 691392445.96 items/sec
  Run 3: 741007201.25 items/sec
  Run 4: 653830833.48 items/sec
  Avg: 706841204.18 items/sec
  Min: 653830833 items/sec
  Max: 741134336 items/sec

─ Zig ─────────────────────
  Warm-up: 723219200.30 items/sec
  Run 1: 758785862.03 items/sec
  Run 2: 772179430.36 items/sec
  Run 3: 758984070.52 items/sec
  Run 4: 795511573.62 items/sec
  Avg: 771365234.13 items/sec
  Min: 758785862 items/sec
  Max: 795511574 items/sec

─ Binary Size ───────────────
  Go: 1.50MB
  Rust: 388.00KB
  Zig: 2.28MB
```

## สรุปผลเปรียบเทียบ

| Metric | Go | Rust | Zig | Winner |
|--------|-----|------|-----|---------|
| **Throughput (avg)** | 699M items/sec | 706M items/sec | **771M items/sec** | **Zig** |
| **Throughput (min)** | 649M items/sec | 653M items/sec | **758M items/sec** | **Zig** |
| **Variance** | ~13% | ~13% | **~5%** | **Zig** |
| **Binary Size** | 1.50MB | **388KB** | 2.28MB | **Rust** |
| **Dependencies** | stdlib only | **stdlib only** | **stdlib only** | tie |

## Key Insights

1. **Zig ชนะทั้ง throughput และ stability** — 771M items/sec เร็วกว่า Go ~10% และมี variance เพียง 5% เพราะ ReleaseFast ปิด bounds checks ทำให้ tight policy loop เป็น optimal branch sequence
2. **Go กับ Rust ใกล้เคียงมาก** — ห่างกันเพียง ~1% (699M vs 706M); ทั้งสองมี variance ใกล้กัน (~13%) จาก Docker VM CPU frequency scaling
3. **Rust ชนะ binary size ขาดลอย** — 388KB เล็กกว่า Go 3.9x และเล็กกว่า Zig 5.9x เหมาะมากสำหรับ sidecar ที่ต้องการ footprint ต่ำสุด
4. **ทั้ง 3 ภาษาไม่มี external dependencies** — stdlib ล้วนๆ: Go (`bufio`, `strconv`), Rust (`std::fs`), Zig (`std.fs`, `std.mem`)
5. **LOOPS count สำคัญ** — จาก LOOPS=200 (2ms/run → variance 2.7x) เป็น LOOPS=150000 (~1s/run → variance <15%); ต้องให้แต่ละ Docker run ใช้เวลา ≥1 วินาทีเพื่อผลที่เชื่อถือได้

## Technical Notes

### Go
- `bufio.Scanner` อ่าน CSV line-by-line → `strings.Split` + `strconv.ParseFloat`
- `process()` ใช้ bare `int`/`uint64` counters — Go compiler optimize loop ได้ดี
- `time.Now()` + `time.Since()` → nanosecond precision

### Rust
- `fs::read_to_string` + `.lines()` iterator — zero-copy line splitting
- `saturating_sub(1)` สำหรับ cooldown decrement — ป้องกัน underflow โดยไม่ต้องตรวจ branch
- `Instant::now().elapsed().as_nanos()` → `u128` nanoseconds

### Zig
- `std.fs.cwd().readFileAlloc` + `std.mem.splitScalar` — อ่านทั้งไฟล์แล้ว split ใน memory
- `std.mem.trim` สำหรับ whitespace ก่อน parse float
- `std.fmt.parseFloat(f64, ...)` — safe float parsing with error union
