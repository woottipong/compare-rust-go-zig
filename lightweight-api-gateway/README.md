# Lightweight API Gateway

เปรียบเทียบการทำ Lightweight API Gateway ด้วย Go, Rust, และ Zig

## วัตถุประสงค์
สร้าง API Gateway ขนาดเล็กที่มี JWT Authentication, Rate Limiting, และ Reverse Proxy (ฝึก Concurrency, Middleware Pattern, และ HTTP Performance)

## โครงสร้างโปรเจกต์
```
lightweight-api-gateway/
├── go/                 # Go + net/http + middleware chain
├── rust/               # Rust + axum + tower middleware
├── zig/                # Zig + manual HTTP parsing
├── test-data/          # Test endpoints และ mock services
├── benchmark/          # Scripts สำหรับ benchmark
└── README.md           # คำแนะนำ build/run + ตาราง comparison
```

## Dependencies

### Go
```bash
go get github.com/golang-jwt/jwt/v5
go get github.com/gin-gonic/gin  # optional for routing
```

### Rust
```bash
cargo add axum tokio tower tower-http
cargo add jsonwebtoken serde
```

### Zig
- ไม่ต้อง dependencies พิเศษ (ใช้ std lib เท่านั้น)

## Build & Run

### Go
```bash
cd go
go mod init lightweight-api-gateway
go build -o ../bin/gateway-go .
../bin/gateway-go :8080 http://localhost:3000
```

### Rust
```bash
cd rust
cargo build --release
./target/release/lightweight-api-gateway :8080 http://localhost:3000
```

### Zig
```bash
cd zig
zig build -Doptimize=ReleaseFast
./zig-out/bin/lightweight-api-gateway :8080 http://localhost:3000
```

## Docker Build & Run

### Build Images
```bash
# Build all images
docker build -t gw-go   go/
docker build -t gw-rust rust/
docker build -t gw-zig  zig/
```

### Docker Run (HTTP Mode)
```bash
# Create Docker network for gateway + backend
docker network create gw-net

# Start mock backend
docker run -d --network gw-net --name mock-backend -p 3000:3000 \
  python:3.12-slim python3 -c "
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self): self.send_response(200); self.end_headers(); self.wfile.write(b'OK')
    def log_message(self,*a): pass
HTTPServer(('0.0.0.0',3000),H).serve_forever()
"

# Run Gateway
# Go
docker run -d --network gw-net -p 8080:8080 --name gateway-go gw-go \
  0.0.0.0:8080 http://mock-backend:3000

# Rust
docker run -d --network gw-net -p 8080:8080 --name gateway-rust gw-rust \
  0.0.0.0:8080 http://mock-backend:3000

# Zig
docker run -d --network gw-net -p 8080:8080 --name gateway-zig gw-zig \
  0.0.0.0:8080 http://mock-backend:3000
```

### Test Gateway
curl http://localhost:8080/api/test

## Benchmark
```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/lightweight-api-gateway_YYYYMMDD_HHMMSS.txt`

*(Methodology: `wrk -t4 -c50 -d3s` ผ่าน Docker network — mock backend อยู่ใน container เดียวกัน)*

## การเปรียบเทียบ

| Aspect | Go | Rust | Zig |
|--------|----|------|-----|
| **HTTP Server** | Fiber v2 (fasthttp) | axum + hyper | Zap (facil.io) |
| **Middleware** | Fiber handlers | tower layers | Zap middleware |
| **JWT Validation** | simple string check | simple string check | simple string check |
| **Rate Limiting** | sync.Map + Mutex | DashMap | StringHashMap + Mutex |
| **Performance** | ~54,919 req/s | ~57,056 req/s | ~52,103 req/s |
| **Memory Usage** | 11,344 KB | 2,528 KB | 27,680 KB |
| **Binary Size** | 9.1MB | 1.6MB | 233KB |
| **Code Lines** | 209 | 173 | 146 |

## Benchmark Results

```
╔══════════════════════════════════════════╗
║   Lightweight API Gateway Benchmark      ║
╚══════════════════════════════════════════╝
  Tool     : wrk -t4 -c50 -d3s
  Mode     : Docker network

── Go (Fiber) ─────────────────────────────────
  Requests/sec : 54919.00
  Avg Latency  : 0.91ms

── Rust (axum) ────────────────────────────────
  Requests/sec : 57056.00
  Avg Latency  : 0.88ms

── Zig (Zap) ──────────────────────────────────
  Requests/sec : 52103.00
  Avg Latency  : 0.96ms

── Binary Size ───────────────────────────────
  Go  : 9.1MB
  Rust: 1.6MB
  Zig : 233KB

── Code Lines ────────────────────────────────
  Go  : 209 lines
  Rust: 173 lines
  Zig : 146 lines
```

**Key insight**: ทุกภาษาอยู่ใน ballpark เดียวกัน (~50-57K req/s) เมื่อใช้ async framework ที่เหมาะสม

### Summary

## สรุปผล
- **Rust (axum)** เร็วสุด 57,056 req/s, memory ต่ำสุด (2.5MB) — Tokio async I/O เป็น winner
- **Go (Fiber)** ใกล้เคียง Rust มาก (54,919 req/s, ~4% ช้ากว่า) — เหมาะสุดสำหรับ production ที่เน้น DX
- **Zig (Zap)** อยู่ที่ 52,103 req/s — ใกล้เคียง Go/Rust เมื่อใช้ proper async framework
- **Zig manual** เพียง 8,599 req/s — single-threaded ทำให้ช้า 6x เทียบ Zap
- Zap เร็วกว่า manual Zig **6x** เพราะ facil.io ใช้ async event loop + multi-threaded workers
- Zig binary เล็กสุด (233KB) แต่ memory สูงสุดเมื่อใช้ Zap (27MB เพราะ facil.io worker pool)
- ทุกภาษาอยู่ใน ballpark เดียวกัน (~50-57K req/s) เมื่อใช้ async framework ที่เหมาะสม

## หมายเหตุ
- **Go**: ใช้ Fiber v2 (fasthttp underneath) — middleware chain, JWT validation, rate limiting
- **Rust**: ใช้ axum + tower middleware — type-safe routing, DashMap rate limiter  
- **Zig**: ใช้ Zap (facil.io C library) — multi-threaded async, code กระชับสุด (146 lines)
- **Zig manual** (main_manual.zig): single-threaded, เก็บไว้เพื่อเปรียบเทียบ
- **Test Setup**: mock backend service + wrk (4 threads, 50 connections, 3s duration)
- **Benchmark**: วัด throughput (req/s) — metric หลักสำหรับ API Gateway

## ข้อควรระวัง (Technical Considerations)

### ⚠️ Zap Dynamic Library
`libfacil.io.dylib` ถูก bundle แบบ dynamic library:
- หาก rebuild Zig → ต้อง `cp .zig-cache/o/*/libfacil.io.dylib zig-out/bin/` ใหม่ทุกครั้ง
- หรือใช้ `install_name_tool` สำหรับ static linking (ยังไม่ได้ทดลอง)
- สาเหตุ: facil.io เป็น C library ที่ compile เป็น shared library บน macOS

### ℹ️ Zig Zap Memory Usage
Zap ใช้ memory สูง (27MB vs 2.5MB Rust):
- **สาเหตุ**: facil.io worker pool (4 threads) + per-request buffers
- **Trade-off**: Performance 52K req/s vs memory usage
- **ถ้าต้องการ low memory**: ใช้ `main_manual.zig` (single-threaded, 8K req/s, 1.4MB)
- **Tuning options**: ลด `threads`/`workers` ใน `zap.start()` หรือใช้ `max_clients`

### ℹ️ JWT Implementation
ทุกภาษาใช้ simple string validation:
```go
tokenString == "valid-test-token"
```
- **เหตุผล**: เหมาะสำหรับ benchmark — ไม่ต้อง load crypto keys
- **Production**: ควรใช้ real JWT signing/verification
  - Go: `github.com/golang-jwt/jwt/v5` + HMAC/RS256
  - Rust: `jsonwebtoken` crate + validation
  - Zig: ใช้ crypto libraries หรือ implement HMAC-SHA256
