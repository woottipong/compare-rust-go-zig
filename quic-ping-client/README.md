# QUIC Ping Client: Go vs Rust vs Zig

จำลอง UDP ping loop (PING/PONG) เพื่อวัด round-trip latency และ runtime overhead ต่อ request ระหว่าง Go, Rust, และ Zig

## โครงสร้าง

```text
quic-ping-client/
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
│   └── mock_udp.py      # Python UDP echo server on port 56000
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies

- Docker (for benchmark)
- Python 3 (for mock UDP server)

## Build

```bash
# Go
unset GOROOT && go build -o ../bin/quic-ping-client-go ./go

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

อ้างอิงจาก: `benchmark/results/quic-ping-client_20260227_124735.txt`

```
Target  : host.docker.internal:56000
Repeats : 10,000 ping-pong round trips
Mode    : Docker
```

| Run | Go | Rust | Zig |
|-----|---:|-----:|----:|
| Warm-up | 1610ms | 1534ms | 1636ms |
| Run 2 | 1582ms | 1513ms | 1573ms |
| Run 3 | 1585ms | 1609ms | 1540ms |
| Run 4 | 1601ms | 1608ms | 1560ms |
| Run 5 | 1594ms | 1453ms | 1499ms |
| **Avg** | **1590ms** | **1545ms** | **1543ms** |
| Min | 1582ms | 1453ms | 1499ms |
| Max | 1601ms | 1609ms | 1573ms |

### Summary

| Metric | Go | Rust | Zig |
|--------|---:|-----:|----:|
| Avg Time | 1,590ms | 1,545ms | **1,543ms** |
| Avg Latency | 0.159ms | 0.145ms | **0.150ms** |
| Throughput | 6,274 items/s | **6,883 items/s** | 6,672 items/s |
| Binary Size | 2.1MB | **388KB** | 1.4MB |
| Code Lines | 89 | **53** | 94 |

## Key Insight

**ทั้ง 3 ภาษาแทบเหมือนกัน — UDP round-trip เป็น bottleneck**

งานนี้ I/O-bound 100% — เวลาส่วนใหญ่คือรอ UDP round-trip ระหว่าง Docker container → host → Python server → กลับ:

- **Zig** เร็วสุดเล็กน้อย (1,543ms avg) ใช้ raw C socket API `sendto/recvfrom` โดยตรง
- **Rust** ใกล้เคียง (1,545ms avg) ด้วย `UdpSocket` ซึ่ง thin wrapper บน BSD socket
- **Go** ช้าสุดเล็กน้อย (1,590ms avg) เพราะ Go runtime ใช้ network poller + goroutine scheduling ที่มี overhead มากกว่า

ทั้ง 3 ภาษา throughput ~6,000-7,000 items/sec — ตัวเลขนี้คือ limit ของ UDP loopback ผ่าน Docker Network NAT ไม่ใช่ limit ของภาษา

**Rust binary เล็กสุด 388KB** — ไม่มี runtime overhead
