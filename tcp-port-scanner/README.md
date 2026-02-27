# TCP Port Scanner: Go vs Rust vs Zig

สแกนช่วง TCP port แบบ sequential timeout-based แล้ววัด throughput ของงาน scan ซ้ำหลายรอบ

## โครงสร้าง

```text
tcp-port-scanner/
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
│   └── mock_tcp.py        # Python server: ports 54000,54002,54004,54006,54008 = open
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies

- Docker (for benchmark)
- Python 3 (for mock TCP server)

## Build

```bash
# Go
unset GOROOT && go build -o ../bin/tcp-port-scanner-go ./go

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

อ้างอิงจาก: `benchmark/results/tcp-port-scanner_20260227_020446.txt`

```
Target  : host.docker.internal:54000-54009 (10 ports, 5 open)
Repeats : 200
Total   : 2,000 port scans per language
Timeout : 50ms per port
```

| Run | Go | Rust | Zig |
|-----|---:|-----:|----:|
| Warm-up | 2669ms | 2424ms | 3396ms |
| Run 2 | 2744ms | 6222ms | 4764ms |
| Run 3 | 2992ms | 6157ms | 6385ms |
| Run 4 | 2632ms | 6506ms | 6041ms |
| Run 5 | 2692ms | 5186ms | 5515ms |
| **Avg** | **2765ms** | **6017ms** | **5676ms** |
| Min | 2632ms | 5186ms | 4764ms |
| Max | 2992ms | 6506ms | 6385ms |

### Summary

| Metric | Go | Rust | Zig |
|--------|---:|-----:|----:|
| Avg Time | **2,765ms** | 6,017ms | 5,676ms |
| Throughput | **742.94 items/s** | 385.67 items/s | 362.66 items/s |
| Binary Size | 2.1MB | **388KB** | 1.4MB |
| Code Lines | 72 | **61** | 100 |

## Key Insight

**Go ชนะ ~2× เพราะ DNS caching ใน net package**

งานนี้ I/O-bound ทั้งหมด — เวลาส่วนใหญ่ใช้ไปกับ TCP connect + DNS resolution:

- **5 open ports**: connect สำเร็จทันที
- **5 closed ports**: TCP RST กลับมาทันที
- แต่ total scan ใช้เวลา 2-6 วินาที เพราะ DNS resolution overhead

**สาเหตุที่ Go เร็วกว่า:**
- Go `net.DialTimeout("tcp", "host:port", timeout)` → Go runtime cache DNS lookup อัตโนมัติ
- Rust `"host:port".to_socket_addrs()` → ทำ DNS resolution ซ้ำทุก port ทุก repeat (2,000 ครั้ง)
- Zig ใช้ `getaddrinfo()` via C → overhead ต่อ call คล้าย Rust

**Rust binary เล็กที่สุด 388KB** (vs Go 2.1MB, Zig 1.4MB) — zero-cost abstractions ใน release mode
