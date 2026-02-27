# Custom BitTorrent Client: Go vs Rust vs Zig

จำลอง BitTorrent peer handshake (68-byte TCP exchange) ซ้ำหลายรอบ เพื่อวัด throughput ของ TCP connection setup + binary protocol parsing ระหว่าง Go, Rust, Zig

## โครงสร้าง

```text
custom-bittorrent-client/
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
│   ├── mock_peer.py      # Python TCP echo server (single-threaded)
│   └── Dockerfile
├── benchmark/
│   ├── results/
│   └── run.sh            # Docker network: btc-net
└── README.md
```

## Dependencies

- Docker (for benchmark + mock peer)

## Build

```bash
# Go
unset GOROOT && go build -o ../bin/btc-go ./go

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

อ้างอิงจาก: `benchmark/results/custom-bittorrent-client_20260227_130602.txt`

```
Target  : mock-peer:6881 (Docker network: btc-net)
Repeats : 6,000 handshakes
Protocol: BitTorrent handshake (68 bytes send + 68 bytes recv per connection)
```

| Run | Go | Rust | Zig |
|-----|---:|-----:|----:|
| Warm-up | 1738ms | 2492ms | 4300ms |
| Run 2 | 2233ms | 4177ms | 4296ms |
| Run 3 | 1938ms | 4482ms | 5335ms |
| Run 4 | 1761ms | 4557ms | 5588ms |
| Run 5 | 2229ms | 4192ms | 5316ms |
| **Avg** | **2040ms** | **4352ms** | **5133ms** |
| Min | 1761ms | 4177ms | 4296ms |
| Max | 2233ms | 4557ms | 5588ms |

### Summary

| Metric | Go | Rust | Zig |
|--------|---:|-----:|----:|
| Avg Time | **2,040ms** | 4,352ms | 5,133ms |
| Avg Latency | **0.371ms** | 0.699ms | 0.886ms |
| Throughput | **2,691 items/s** | 1,431 items/s | 1,129 items/s |
| Binary Size | 2.2MB | **388KB** | 1.4MB |
| Code Lines | **118** | 125 | 123 |

## Key Insight

**Go ชนะ 2× เหนือ Rust และ 2.5× เหนือ Zig — เพราะ DNS caching**

ทุก handshake ต้องผ่าน 3 ขั้นตอน: DNS resolve → TCP connect → send/recv 68 bytes

| ขั้นตอน | Go | Rust | Zig |
|---------|-----|------|-----|
| **DNS resolve** | ครั้งแรกเท่านั้น (Go runtime cache) | ทุก iteration (OS resolver) | ทุก iteration (`getaddrinfo`) |
| **TCP connect** | `net.DialTimeout` | `TcpStream::connect_timeout` | C `connect()` |
| **Data exchange** | `io.ReadFull` | `read_exact` | C `send/recv` |

- **Go**: `net.DialTimeout("tcp", "mock-peer:6881", ...)` → Go runtime cache DNS ภายใน → ไม่มี DNS overhead หลัง iteration แรก
- **Rust**: `"mock-peer:6881".to_socket_addrs()` ถูกเรียกใน `do_handshake()` ทุก iteration → DNS query ทุก 6,000 ครั้ง
- **Zig**: `getaddrinfo()` ถูกเรียกใน `connectSocket()` ทุก iteration → เช่นเดียวกับ Rust

pattern เดียวกับ tcp-port-scanner: ภาษาที่ cache DNS ชนะในงาน high-frequency TCP connection

**Rust binary เล็กสุด 388KB** — zero-cost abstractions ใน release build
