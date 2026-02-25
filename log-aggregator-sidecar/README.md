# Log Aggregator Sidecar

เปรียบเทียบการทำ Log Aggregator Sidecar ด้วย Go, Rust, และ Zig

## วัตถุประสงค์

ดึง Log จาก Container ไปแปลงเป็น JSON และส่งต่อ (ฝึกการทำโปรแกรมตัวเล็กแต่ประสิทธิภาพสูง)

## โครงสร้างโปรเจกต์

```
log-aggregator-sidecar/
├── go/                 # Go + fsnotify + HTTP client
├── rust/               # Rust + notify + tokio
├── zig/                # Zig + std.fs.Watcher
├── test-data/          # Sample log files
├── benchmark/          # Scripts สำหรับ benchmark
└── README.md           # คำแนะนำ build/run + ตาราง comparison
```

## Dependencies

### Go
```bash
go mod init log-aggregator-sidecar
go get github.com/fsnotify/fsnotify
```

### Rust
```bash
cargo add notify tokio reqwest serde serde_json
```

### Zig
- Standard library เท่านั้น (ไม่ต้องการ external dependencies)

## Build & Run

### Go
```bash
cd go
go build -o ../bin/log-aggregator-go .
../bin/log-aggregator-go --input test-data/app.log --output http://localhost:9200
```

### Rust
```bash
cd rust
cargo build --release
./target/release/log-aggregator-sidecar --input test-data/app.log --output http://localhost:9200
```

### Zig
```bash
cd zig
zig build -Doptimize=ReleaseFast
./zig-out/bin/log-aggregator --input test-data/app.log --output http://localhost:9200
```

## Docker Build & Run

### Build Images
```bash
docker build -t las-go   go/
docker build -t las-rust rust/
docker build -t las-zig  zig/
```

### Docker Run
```bash
# Mount log directory and forward to Elasticsearch
docker run --rm -v "$(pwd)/test-data:/logs:ro" \
  las-go --input /logs/app.log --output http://elasticsearch:9200
```

## Test Data Generation
```bash
cd test-data
# Generate 100K lines of mixed log formats
python3 -c "
import random, time, json, sys
levels = ['INFO', 'WARN', 'ERROR', 'DEBUG']
apps = ['auth', 'payment', 'api', 'worker']
for i in range(100000):
    level = random.choice(levels)
    app = random.choice(apps)
    ts = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(time.time() - random.randint(0, 86400)))
    msg = f'User {random.randint(1000,9999)} {\"login\" if level==\"INFO\" else \"failed\"} from {random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}'
    print(f'{ts} {level} {app}[{random.randint(1,10)}]: {msg}')
" > app.log
```

## Benchmark

```bash
cd log-aggregator-sidecar
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/log-aggregator-sidecar_YYYYMMDD_HHMMSS.txt`

รัน 5 ครั้ง: 1 warm-up + 4 วัดผล

## การเปรียบเทียบ

| Aspect | Go | Rust | Zig |
|--------|----|------|-----|
| **File Watcher** | fsnotify | notify crate | std.fs.Watcher |
| **Parsing** | bufio.Scanner + regex | regex crate | manual parsing |
| **Buffering** | bytes.Buffer | Vec<u8> | std.ArrayList |
| **HTTP Client** | net/http | reqwest | std.http.Client |
| **Performance** | ~XX lines/s | ~XX lines/s | ~XX lines/s |
| **Memory Usage** | XX MB | XX MB | XX MB |
| **Binary Size** | X.XMB | XXXKB | XXXKB |
| **Code Lines** | XXX | XXX | XXX |

## ผลการวัด (Benchmark Results)

```
╔══════════════════════════════════════════╗
║     Log Aggregator Sidecar Benchmark     ║
╚══════════════════════════════════════════╝
  Test Data: 100K lines (7.2MB)
  Runs    : 5 (1 warm-up)

── Go   ───────────────────────────────────────
  Run 1 (warm-up): XXXX lines/s
  Run 2           : XXXX lines/s
  Run 3           : XXXX lines/s
  Run 4           : XXXX lines/s
  Run 5           : XXXX lines/s
  ─────────────────────────────────────────
  Avg: XXXX lines/s  |  Min: XXXX  |  Max: XXXX
  Memory  : XX MB
  Binary  : X.XMB

── Rust ───────────────────────────────────────
  Run 1 (warm-up): XXXX lines/s
  Run 2           : XXXX lines/s
  Run 3           : XXXX lines/s
  Run 4           : XXXX lines/s
  Run 5           : XXXX lines/s
  ─────────────────────────────────────────
  Avg: XXXX lines/s  |  Min: XXXX  |  Max: XXXX
  Memory  : XX MB
  Binary  : XXXKB

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): XXXX lines/s
  Run 2           : XXXX lines/s
  Run 3           : XXXX lines/s
  Run 4           : XXXX lines/s
  Run 5           : XXXX lines/s
  ─────────────────────────────────────────
  Avg: XXXX lines/s  |  Min: XXXX  |  Max: XXXX
  Memory  : XX MB
  Binary  : XXXKB

── Code Lines ────────────────────────────────
  Go  : XXX lines
  Rust: XXX lines
  Zig : XXX lines
```

**Key insight**: (จะอัปเดตหลังจากรัน benchmark)

## สรุปผล

- **Go**: (จะอัปเดตหลังจากรัน benchmark)
- **Rust**: (จะอัปเดตหลังจากรัน benchmark)
- **Zig**: (จะอัปเดตหลังจากรัน benchmark)

## หมายเหตุ

- **Go**: ใช้ `fsnotify` สำหรับ file watching — ง่ายต่อการ implement แต่ binary ใหญ่
- **Rust**: ใช้ `notify` crate + `tokio` — async I/O และ memory safety
- **Zig**: ใช้ `std.fs.Watcher` — binary เล็กสุด แต่ต้อง implement manual parsing
- **Test Data**: 100K lines mixed log formats (INFO/WARN/ERROR/DEBUG)
- **Benchmark**: วัด throughput (lines/sec) — metric หลักสำหรับ log processing

## ทักษะที่ฝึก

| ภาษา | ทักษะ |
|------|------|
| **Go** | File watching, regex parsing, HTTP client, goroutines |
| **Rust** | Async I/O, error handling, zero-copy parsing |
| **Zig** | Manual memory management, system calls, binary protocols |
