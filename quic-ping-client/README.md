# QUIC Ping Client: Go vs Rust vs Zig

โปรเจกต์นี้จำลอง QUIC ping loop บน UDP transport (mock handshake/ping flow) เพื่อเทียบ runtime overhead และ latency ต่อ request ระหว่าง Go, Rust, และ Zig

## โครงสร้าง

```text
quic-ping-client/
├── go/
├── rust/
├── zig/
├── test-data/
│   └── mock_udp.py
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูกบันทึกใน `benchmark/results/`

## Benchmark Results

อ้างอิงผลล่าสุดจาก:
`benchmark/results/quic-ping-client_20260226_234119.txt`

```
── Go
  Avg: 503ms  |  Min: 498ms  |  Max: 511ms
  Throughput: 6013.38 items/sec

── Rust
  Avg: 480ms  |  Min: 476ms  |  Max: 489ms
  Throughput: 6284.24 items/sec

── Zig
  Avg: 476ms  |  Min: 473ms  |  Max: 480ms
  Throughput: 6338.14 items/sec
```

### Summary

| Metric | Go | Rust | Zig |
|---|---:|---:|---:|
| Avg Time | 503ms | 480ms | **476ms** |
| Throughput | 6013.38 items/s | 6284.24 items/s | **6338.14 items/s** |
| Binary Size | 2.1MB | **388KB** | 1.4MB |

**Insight:** Zig เร็วสุดเล็กน้อยใน workload นี้ ขณะที่ Rust ใกล้เคียงมากและยังได้ binary เล็กสุด.
