# SQLite Query Engine: Go vs Rust vs Zig

โปรเจกต์นี้ benchmark การ query SQLite แบบอ่าน raw B-tree page (ไม่ใช้ sqlite client library) เพื่อเปรียบเทียบประสิทธิภาพการสแกนข้อมูลระหว่าง Go, Rust, Zig

## วัตถุประสงค์
- ฝึก parsing SQLite file format (varint, record header, table B-tree)
- เปรียบเทียบ throughput ของการ scan/filter (`cpu_pct > 80.0`)
- วัด binary size และ code size ของแต่ละภาษา

## โครงสร้าง

```text
sqlite-query-engine/
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
│   └── metrics.db
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies
- Docker
- Python 3 (สำหรับ generate test database)

## Build & Run

### Generate test data

```bash
python3 test-data/generate.py
```

### Go

```bash
unset GOROOT && go build -o ../bin/sqlite-query-engine-go .
../bin/sqlite-query-engine-go ../test-data/metrics.db 2000
```

### Rust

```bash
cargo build --release
./target/release/sqlite-query-engine ../test-data/metrics.db 2000
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/sqlite-query-engine ../test-data/metrics.db 2000
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/sqlite-query-engine_YYYYMMDD_HHMMSS.txt`

(benchmark รัน 5 ครั้ง: 1 warm-up + 4 measured ผ่าน Docker)

## Benchmark Results

วัดด้วย `REPEATS=2000` บน 100,000 rows (25,034 matching cpu_pct > 80.0), Docker-based, Apple M-series

```text
╔══════════════════════════════════════════╗
║      SQLite Query Engine Benchmark       ║
╚══════════════════════════════════════════╝
  Input    : test-data/metrics.db
  Repeats  : 2000
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 2166ms
  Run 2           : 2171ms
  Run 3           : 2177ms
  Run 4           : 2184ms
  Run 5           : 2174ms
  ─────────────────────────────────────────
  Avg: 2176ms  |  Min: 2171ms  |  Max: 2184ms

  Total processed: 250068000
  Processing time: 2.174s
  Average latency: 0.000009ms
  Throughput     : 115002830.18 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 1410ms
  Run 2           : 1398ms
  Run 3           : 1839ms
  Run 4           : 1537ms
  Run 5           : 1490ms
  ─────────────────────────────────────────
  Avg: 1566ms  |  Min: 1398ms  |  Max: 1839ms

  Total processed: 250068000
  Processing time: 1.490s
  Average latency: 0.000006ms
  Throughput     : 167805415.39 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 768ms
  Run 2           : 767ms
  Run 3           : 763ms
  Run 4           : 768ms
  Run 5           : 753ms
  ─────────────────────────────────────────
  Avg: 762ms  |  Min: 753ms  |  Max: 768ms

  Total processed: 250068000
  Processing time: 0.753s
  Average latency: 0.000003ms
  Throughput     : 332074284.07 items/sec

── Binary Size ───────────────────────────────
  Go  : 1.6MB
  Rust: 388KB
  Zig : 2.2MB

── Code Lines ────────────────────────────────
  Go  : 319 lines
  Rust: 346 lines
  Zig : 298 lines
```

ผลลัพธ์ถูกบันทึกไว้ที่:
`benchmark/results/sqlite-query-engine_20260227_012657.txt`

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | 2,176ms | 1,566ms | **762ms** |
| Min/Max time | 2,171/2,184ms | 1,398/1,839ms | **753/768ms** |
| Total processed | 250,068,000 | 250,068,000 | 250,068,000 |
| Throughput | 115,002,830 items/sec | 167,805,415 items/sec | **332,074,284 items/sec** |
| Average latency | 0.000009ms | 0.000006ms | **0.000003ms** |
| Binary size | 1.6MB | **388KB** | 2.2MB |
| Code lines | 319 | 346 | **298** |

## Key Insights

1. **Zig ชนะ throughput** ที่ 332M items/sec — เร็วกว่า Rust 1.98×, เร็วกว่า Go 2.89× ในงาน B-tree parsing + varint decode
2. **Zig มี variance ต่ำ** (753–768ms, ~2%) เพราะ ReleaseFast + predictable memory layout ให้ผลคงที่
3. **Rust มี variance สูงกว่า** (1,398–1,839ms, ~31%) — Docker CPU scheduling noise มีผลมากในรันที่สั้น
4. **Rust ชนะ binary size** ที่ 388KB (เล็กกว่า Go 4.1×, เล็กกว่า Zig 5.7×) เหมาะกับ embedding
5. **Total processed = rows_scanned + rows_matching**: 100,000 × 2,000 + 25,034 × 2,000 = 250,068,000 ✓

## Technical Notes

- **SQLite storage optimization**: Python's `round(random.uniform(), 2)` produces exact integers (e.g. 50.0) for ~1% of rows. SQLite stores these as type 1 (1-byte int), not type 7 (float64). All 3 implementations handle this via `readRealCol` that dispatches on serial type.
- **INTEGER PRIMARY KEY null placeholder**: `id` column is stored as NULL (serial type 0, 0 bytes) in record body because SQLite aliases it to the rowid. Column offsets: col[0]=id(0 bytes), col[1]=hostname, col[2]=cpu_pct.
- **Load phase outside timer**: entire `.db` file read into memory once; hot loop only does in-memory B-tree scan × REPEATS.
- **Go**: `encoding/binary.BigEndian` + `math.Float64frombits` for float decode
- **Rust**: `u16::from_be_bytes` + `f64::from_bits` — no external crates
- **Zig**: `std.mem.readInt(..., .big)` + `@bitCast` — ReleaseFast enables aggressive LLVM optimizations
