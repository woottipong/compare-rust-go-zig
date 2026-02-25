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

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| **Throughput (Avg)** | ~22,750 l/s | ~25,782 l/s | ~54,014 l/s |
| **Throughput (Min)** | ~20,480 l/s | ~25,244 l/s | ~48,260 l/s |
| **Throughput (Max)** | ~24,423 l/s | ~26,835 l/s | ~58,102 l/s |
| **Binary Size** | 5.9MB | 5.9MB | 7.5MB |
| **Code Lines** | 370 | 385 | 448 |
| **File Watcher** | fsnotify | notify crate | polling (500ms) |
| **HTTP Client** | net/http | reqwest + rustls | std.http.Client |
| **Concurrency** | goroutines | tokio async | Thread + Mutex |

## ผลการวัด (Benchmark Results)

```
╔══════════════════════════════════════════╗
║     Log Aggregator Sidecar Benchmark     ║
╚══════════════════════════════════════════╝
  Test Data: 100K lines
  Runs    : 5 (1 warm-up + 4 วัดผล)
  Mode    : Docker one-shot

── Go     ────────────────────────────────────────
  Run 1 (warm-up): 24821.05 lines/sec
  Run 2           : 23932.01 lines/sec
  Run 3           : 22166.69 lines/sec
  Run 4           : 20479.68 lines/sec
  Run 5           : 24422.83 lines/sec
  ─────────────────────────────────────────────
  Avg: 22,750 l/s  |  Min: 20,480  |  Max: 24,423
  Binary  : 5.9MB

── Rust   ────────────────────────────────────────
  Run 1 (warm-up): 25467.30 lines/sec
  Run 2           : 25395.60 lines/sec
  Run 3           : 25244.07 lines/sec
  Run 4           : 26835.05 lines/sec
  Run 5           : 25655.21 lines/sec
  ─────────────────────────────────────────────
  Avg: 25,782 l/s  |  Min: 25,244  |  Max: 26,835
  Binary  : 5.9MB

── Zig    ────────────────────────────────────────
  Run 1 (warm-up): 58088.01 lines/sec
  Run 2           : 54904.48 lines/sec
  Run 3           : 54790.52 lines/sec
  Run 4           : 58101.80 lines/sec
  Run 5           : 48260.41 lines/sec
  ─────────────────────────────────────────────
  Avg: 54,014 l/s  |  Min: 48,260  |  Max: 58,102
  Binary  : 7.5MB

── Code Lines ────────────────────────────────────
  Go  : 370 lines
  Rust: 385 lines
  Zig : 448 lines
```

**Key insight**: **Zig ชนะขาด ~2.4x เหนือ Rust และ ~2.4x เหนือ Go** เพราะใช้ `readToEndAlloc` + `splitScalar` อ่านไฟล์ครั้งเดียวทั้งหมดแทนที่จะ read line-by-line และ batch flush แบบ sync ไม่มี async overhead

## สรุปผล

- **Go**: 22,750 l/s — ง่าย implement, `net/http` connection reuse ต้อง drain body ก่อน close
- **Rust**: 25,782 l/s — consistent ที่สุด variance น้อย, async tokio + reqwest rustls
- **Zig**: 54,014 l/s — เร็วที่สุด ~2.4x, sync I/O + read-entire-file approach ชนะ async overhead

## หมายเหตุ

- **Go**: ใช้ `fsnotify` สำหรับ file watching, ต้อง drain response body เพื่อ reuse connection
- **Rust**: ใช้ `notify` crate + `tokio` async, `reqwest` with `rustls-tls` (no libssl dependency)
- **Zig**: ใช้ polling 500ms แทน inotify (Zig 0.15 ไม่มี `std.fs.Watcher`), `readToEndAlloc` + `splitScalar`
- **Test Data**: 100K lines mixed log formats (INFO/WARN/ERROR/DEBUG)
- **Benchmark**: วัด throughput (lines/sec) ผ่าน Docker one-shot mode

## ทักษะที่ฝึก

| ภาษา | ทักษะ |
|------|------|
| **Go** | File watching, regex parsing, HTTP client, goroutines |
| **Rust** | Async I/O, error handling, zero-copy parsing |
| **Zig** | Manual memory management, system calls, binary protocols |
