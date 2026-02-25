# High-Performance Reverse Proxy

Reverse Proxy พร้อม Load Balancing (Round-robin) เชื่อมต่อ backend servers ผ่าน TCP

---

## วัตถุประสงค์

- ฝึก low-level TCP socket programming ในแต่ละภาษา
- เปรียบเทียบ performance ของ raw TCP proxy vs HTTP framework
- เรียนรู้การ handle concurrent connections (goroutines vs tokio tasks vs threads)

---

## โครงสร้าง

```
high-perf-reverse-proxy/
├── go/
│   ├── main.go         # net/http + httputil.ReverseProxy
│   ├── go.mod
│   └── Dockerfile
├── rust/
│   ├── src/
│   │   └── main.rs     # tokio TcpStream
│   ├── Cargo.toml
│   └── Dockerfile
├── zig/
│   ├── src/
│   │   └── main.zig    # std.posix socket
│   ├── build.zig
│   └── Dockerfile
├── test-data/
├── benchmark/
│   ├── results/
│   └── run.sh          # Docker-based benchmark
└── README.md
```

---

## Dependencies

- **Go**: `net/http`, `httputil`
- **Rust**: `tokio`, `anyhow`, `clap`
- **Zig**: std library only

---

## Build & Run

### Local Build

```bash
# Go
unset GOROOT && go build -o hprp-go .
./hprp-go --port 8080 --backends "localhost:3001,localhost:3002,localhost:3003"

# Rust
cargo build --release
./target/release/hprp-rust --port 8080 --backends "localhost:3001,localhost:3002,localhost:3003"

# Zig
zig build -Doptimize=ReleaseFast
./zig-out/bin/high-perf-reverse-proxy --port 8080 --backends "localhost:3001,localhost:3002,localhost:3003"
```

### Docker Build

```bash
docker build -t hprp-go   go/
docker build -t hprp-rust rust/
docker build -t hprp-zig  zig/
```

---

## Benchmark

```bash
# รัน benchmark ผ่าน Docker (รวม mock backends)
bash benchmark/run.sh
```

---

## ผลการเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Throughput** | **10,065 req/s** | 3,640 req/s | 2,669 req/s |
| **Avg Latency** | **5.60ms** | 12.66ms | 16.24ms |
| **Binary Size** | 5.2MB | **1.2MB** | 2.4MB |
| **Code Lines** | **158** | 160 | 166 |

> Benchmark: `wrk -t4 -c50 -d5s` ผ่าน Docker network พร้อม 3 Python mock backends

---

## ตารางเปรียบเทียบ

| Aspect | Go | Rust | Zig |
|--------|-----|------|-----|
| **Concurrency** | Goroutines + connection pool | Tokio tasks (new conn/request) | Threads (new conn/request) |
| **HTTP Handling** | `httputil.ReverseProxy` (full HTTP) | Raw TCP relay | Raw TCP relay |
| **DNS Resolution** | Built-in | `tokio::net::TcpStream` | `std.net.getAddressList` |
| **Health Check** | HTTP GET `/health` | TCP connect | — |
| **Binary Size** | ใหญ่ (5.2MB) | เล็ก (1.2MB) | กลาง (2.4MB) |

---

## หมายเหตุ

### Go — ชนะขาดด้าน Throughput
- `httputil.ReverseProxy` มี connection pooling (`MaxIdleConns: 200`)
- Reuse connections → ลด TCP handshake overhead
- Trade-off: binary ใหญ่ (5.2MB) จาก fasthttp deps

### Rust — สมดุลดี
- `tokio` async runtime มี overhead เล็กน้อย
- Raw TCP relay (ไม่ parse HTTP) → lower latency กว่า Go ที่ parse ทั้ง request/response
- Binary เล็กที่สุด (1.2MB)

### Zig — Raw & Explicit
- Zero external dependencies — pure stdlib
- `std.net.getAddressList` สำหรับ DNS resolution
- Thread-per-connection model — เรียบง่ายแต่ overhead สูงกว่า async
- Lessons learned:
  - `std.net.Address.resolveIp` รับแค่ IP, ไม่ resolve hostname → ต้องใช้ `getAddressList`
  - อย่า append `Connection: close` ซ้ำหลัง HTTP request (ทำให้ malformed)

---

## Key Lessons

| Issue | Solution |
|-------|----------|
| Zig DNS hostname not resolved | ใช้ `std.net.getAddressList(allocator, host, port)` |
| Zig HTTP malformed | Forward request as-is, ไม่ต้อง append headers ซ้ำ |
| Connection reuse | Go connection pool ชนะขาดใน throughput benchmark |
| Binary size vs performance | Trade-off ชัด — Go เร็วสุดแต่ binary ใหญ่สุด |
