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

## Benchmark
```bash
cd benchmark
./run.sh

# Test with wrk
wrk -t12 -c400 -d30s http://localhost:8080/api/test

# Test with JWT
wrk -t12 -c100 -d30s -H "Authorization: Bearer <token>" http://localhost:8080/api/protected
```

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
