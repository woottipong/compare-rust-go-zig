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

| Aspect | Go | Rust | Zig |
|--------|----|------|-----|
| **HTTP Server** | net/http | axum + hyper | Zap (facil.io) |
| **Concurrency** | goroutines + channels | tokio + mpsc | threads + mutex |
| **Queue** | buffered channel | mpsc channel | lock-free queue |
| **Stats** | sync/atomic | Arc<AtomicU64> | std.atomic.Value |
| **Performance** | ~XX req/s | ~XX req/s | ~XX req/s |
| **Memory Usage** | XX KB | XX KB | XX KB |
| **Binary Size** | X.XMB | XXXKB | XXXKB |
| **Code Lines** | XXX | XXX | XXX |

## ผลการวัด (Benchmark Results)

```
╔══════════════════════════════════════════╗
║      Local ASR/LLM Proxy Benchmark       ║
╚══════════════════════════════════════════╝
  Tool     : wrk -t4 -c50 -d3s
  Mode     : Docker network

── Go ─────────────────────────────────────────
  Run 1 (warm-up): XXXX req/s  latency X.XXms
  Run 2           : XXXX req/s  latency X.XXms
  Run 3           : XXXX req/s  latency X.XXms
  Run 4           : XXXX req/s  latency X.XXms
  Run 5           : XXXX req/s  latency X.XXms
  ─────────────────────────────────────────
  Avg: XXXX req/s  |  Min: XXXX  |  Max: XXXX
  Memory  : XXXX KB
  Binary  : X.XMB

── Rust ────────────────────────────────────────
  Run 1 (warm-up): XXXX req/s  latency X.XXms
  Run 2           : XXXX req/s  latency X.XXms
  Run 3           : XXXX req/s  latency X.XXms
  Run 4           : XXXX req/s  latency X.XXms
  Run 5           : XXXX req/s  latency X.XXms
  ─────────────────────────────────────────
  Avg: XXXX req/s  |  Min: XXXX  |  Max: XXXX
  Memory  : XXXX KB
  Binary  : X.XMB

── Zig ──────────────────────────────────────────
  Run 1 (warm-up): XXXX req/s  latency X.XXms
  Run 2           : XXXX req/s  latency X.XXms
  Run 3           : XXXX req/s  latency X.XXms
  Run 4           : XXXX req/s  latency X.XXms
  Run 5           : XXXX req/s  latency X.XXms
  ─────────────────────────────────────────
  Avg: XXXX req/s  |  Min: XXXX  |  Max: XXXX
  Memory  : XXXX KB
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

- **Go**: ใช้ standard library `net/http` — worker pool กับ buffered channels
- **Rust**: ใช้ `axum` + `tokio` — async worker pool กับ `mpsc` channel
- **Zig**: ใช้ Zap (facil.io C library) — thread pool กับ lock-free queue
- **Mock Backend**: simulate ASR processing time 10-50ms
- **Benchmark**: วัด throughput (req/s) — metric หลักสำหรับ Proxy server

## ทักษะที่ฝึก

| ภาษา | ทักษะ |
|------|------|
| **Go** | Worker pool, channels, `sync/atomic`, `net/http` client |
| **Rust** | `tokio` async, `mpsc` channels, `reqwest`, `Arc<AtomicU64>` |
| **Zig** | Zap framework, thread pool, atomic operations, HTTP client |
