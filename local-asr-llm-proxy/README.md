# Local ASR/LLM Proxy

เปรียบเทียบการทำ ASR/LLM Proxy ด้วย Go, Rust, และ Zig

## วัตถุประสงค์

สร้างตัวจัดการคิว (Queue) สำหรับรับไฟล์เสียงและส่งไปประมวลผลที่ ASR/LLM service (ฝึก Worker Pool, Job Queue, และ Concurrent HTTP Client)

## โครงสร้างโปรเจกต์

```
local-asr-llm-proxy/
├── go/                 # Go + net/http + worker pool
├── rust/               # Rust + axum + tokio
├── zig/                # Zig + Zap (facil.io)
├── test-data/          # Mock backend service
├── benchmark/          # Scripts สำหรับ benchmark
└── README.md           # คำแนะนำ build/run + ตาราง comparison
```

## Dependencies

### Go
- Standard library (`net/http`, `sync`)
- ไม่ต้องการ external dependencies

### Rust
```bash
cargo add axum tokio reqwest serde serde_json uuid num_cpus
```

### Zig
- Zap v0.11.0 (facil.io C library)
- ไม่ต้องการ dependencies เพิ่มเติม

## Build & Run

### Go
```bash
cd go
go mod init local-asr-llm-proxy
go build -o ../bin/asr-proxy-go .
../bin/asr-proxy-go :8080 http://localhost:3000
```

### Rust
```bash
cd rust
cargo build --release
./target/release/local-asr-llm-proxy :8080 http://localhost:3000
```

### Zig
```bash
cd zig
zig build -Doptimize=ReleaseFast
./zig-out/bin/asr-proxy :8080 http://localhost:3000
```

## Docker Build & Run

### Build Images
```bash
# Build all images
docker build -t asr-go   go/
docker build -t asr-rust rust/
docker build -t asr-zig  zig/
```

### Docker Run (HTTP Mode)
```bash
# Create Docker network for proxy + backend
docker network create asr-net

# Start mock backend
docker run -d --network asr-net --name mock-backend -p 3000:3000 \
  golang:1.23-bookworm go run - <<'EOF'
package main
import (
    "encoding/json"
    "math/rand"
    "net/http"
    "time"
)
func main() {
    rand.Seed(time.Now().UnixNano())
    http.HandleFunc("/transcribe", func(w http.ResponseWriter, r *http.Request) {
        time.Sleep(time.Duration(rand.Int63n(40)+10) * time.Millisecond)
        json.NewEncoder(w).Encode(map[string]interface{}{
            "transcription": "mock result",
            "confidence": 0.95,
            "processing_time_ms": rand.Int63n(40)+10,
        })
    })
    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
    })
    http.ListenAndServe(":3000", nil)
}
EOF

# Run Proxy
# Go
docker run -d --network asr-net -p 8080:8080 --name asr-proxy-go asr-go \
  0.0.0.0:8080 http://mock-backend:3000

# Rust
docker run -d --network asr-net -p 8080:8080 --name asr-proxy-rust asr-rust \
  0.0.0.0:8080 http://mock-backend:3000

# Zig
docker run -d --network asr-net -p 8080:8080 --name asr-proxy-zig asr-zig \
  0.0.0.0:8080 http://mock-backend:3000
```

### Test Proxy
```bash
curl -X POST http://localhost:8080/transcribe \
  -H "Content-Type: application/json" \
  -d '{"audio_data":"dGVzdA==","format":"wav","language":"th"}'
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/result_YYYYMMDD_HHMMSS.txt`

*(Methodology: `wrk -t4 -c50 -d3s` ผ่าน Docker network — mock backend อยู่ใน container เดียวกัน)*

## API Specification

### POST /transcribe

Request:
```json
{
    "audio_data": "base64-encoded-audio",
    "format": "wav",
    "language": "th"
}
```

Response:
```json
{
    "job_id": "uuid",
    "status": "completed",
    "transcription": "mock transcription result",
    "processing_time_ms": 25
}
```

### GET /health

Response:
```json
{
    "status": "ok"
}
```

### GET /stats

Response:
```json
{
    "total_processed": 1000,
    "processing_time_s": 15.5,
    "average_latency_ms": 15.5,
    "throughput": 64.5
}
```

## การเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| **Throughput (Avg)** | ~242 req/s | ~1,526 req/s 🏆 | ~115 req/s |
| **Avg Latency** | ~191ms | ~31ms | ~402ms |
| **Memory Usage** | 2,968 KB | 1,248 KB | 72,499 KB |
| **Binary Size** | 5.7MB | 3.8MB | 7.5MB |
| **Code Lines** | 317 | 207 | 221 |
| **HTTP Server** | net/http | axum 0.8 + hyper | Zap (facil.io) |
| **Concurrency** | goroutines + channels | tokio async | zap threads |
| **HTTP Client** | net/http | reqwest + rustls | std.http.Client |

## Benchmark Results

```
╔══════════════════════════════════════════╗
║      Local ASR/LLM Proxy Benchmark       ║
╚══════════════════════════════════════════╝
  Tool     : wrk -t4 -c50 -d3s
  Mode     : Docker network
  Backend  : mock ASR (10-50ms delay per request)

── Go     ──────────────────────────────────────
  Run 1 (warm-up): 253 req/s  latency 181.89ms
  Run 2           : 244 req/s  latency 190.02ms
  Run 3           : 243 req/s  latency 191.05ms
  Run 4           : 245 req/s  latency 189.34ms
  Run 5           : 238 req/s  latency 194.92ms
  ─────────────────────────────────────────
  Avg: 242 req/s  |  Min: 238  |  Max: 245
  Memory  : 2,968 KB
  Binary  : 5.7MB

── Rust   ──────────────────────────────────────
  Run 1 (warm-up): 1514 req/s  latency 31.51ms
  Run 2           : 1522 req/s  latency 31.30ms
  Run 3           : 1521 req/s  latency 31.35ms
  Run 4           : 1551 req/s  latency 30.71ms
  Run 5           : 1511 req/s  latency 31.00ms
  ─────────────────────────────────────────
  Avg: 1,526 req/s  |  Min: 1,511  |  Max: 1,551
  Memory  : 1,248 KB
  Binary  : 3.8MB

── Zig    ──────────────────────────────────────
  Run 1 (warm-up): 123 req/s  latency 376.85ms
  Run 2           : 120 req/s  latency 387.55ms
  Run 3           : 110 req/s  latency 425.41ms
  Run 4           : 120 req/s  latency 390.81ms
  Run 5           : 113 req/s  latency 405.90ms
  ─────────────────────────────────────────
  Avg: 115 req/s  |  Min: 110  |  Max: 120
  Memory  : 72,499 KB
  Binary  : 7.5MB

── Code Lines ────────────────────────────────
  Go  : 317 lines
  Rust: 207 lines
  Zig : 221 lines
```

**Key insight**: **Rust ชนะขาด ~6.3x เหนือ Go และ ~13x เหนือ Zig** เพราะ `tokio` async I/O multiplexes requests บน thread pool โดยไม่บล็อก — 50 concurrent connections ถูก handle โดยไม่ต้องรอ thread ว่าง

**Zig ช้าเพราะ**: `std.http.Client` ใน Zig 0.15 สร้าง client ใหม่ทุก request + Zap (facil.io) ใช้ memory สูง (~72MB) เนื่องจาก thread stack allocation

### Summary

## สรุปผล

- **Go**: 242 req/s — worker pool + buffered channel ใช้ได้แต่ channel เป็น bottleneck เมื่อ backend latency สูง
- **Rust**: 1,526 req/s — async tokio สามารถรับ request ใหม่ขณะรอ backend ได้ ทำให้ throughput สูงสุด
- **Zig**: 115 req/s — `std.http.Client` สร้างใหม่ทุก request มี overhead สูง, Zap framework ใช้ memory สูงมาก

## หมายเหตุ

- **Go**: ใช้ standard library `net/http` — worker pool กับ buffered channels, 1 goroutine ต่อ request
- **Rust**: ใช้ `axum 0.8` + `tokio` async, `reqwest` with `rustls-tls` (no libssl dependency)
- **Zig**: ใช้ Zap (facil.io) + `std.http.Client.fetch` forward ไป backend จริง
- **Mock Backend**: simulate ASR processing time 10-50ms per request
- **Benchmark**: `wrk -t4 -c50 -d3s` วัด throughput (req/s) + latency

## ทักษะที่ฝึก

| ภาษา | ทักษะ |
|------|------|
| **Go** | Worker pool, channels, `sync/atomic`, `net/http` client |
| **Rust** | `tokio` async, `mpsc` channels, `reqwest`, `Arc<AtomicU64>` |
| **Zig** | Zap framework, thread pool, atomic operations, HTTP client |
