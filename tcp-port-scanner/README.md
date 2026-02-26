# TCP Port Scanner: Go vs Rust vs Zig

สแกนช่วง TCP port แบบ timeout-based แล้ววัด throughput ของงาน scan แบบหลายรอบ

## โครงสร้าง

```text
tcp-port-scanner/
├── go/
├── rust/
├── zig/
├── test-data/
│   └── mock_tcp.py
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์บันทึกที่ `benchmark/results/`

## Benchmark Results

อ้างอิงผลล่าสุดจาก:
`benchmark/results/tcp-port-scanner_20260226_233623.txt`

```
── Go
  Avg: 3251ms  |  Min: 3012ms  |  Max: 3485ms
  Throughput: 664.03 items/sec

── Rust
  Avg: 13ms  |  Min: 11ms  |  Max: 18ms
  Throughput: 108365.36 items/sec

── Zig
  Avg: 4099ms  |  Min: 2434ms  |  Max: 7231ms
  Throughput: 276.57 items/sec
```

### Summary

| Metric | Go | Rust | Zig |
|---|---:|---:|---:|
| Avg Time | 3251ms | **13ms** | 4099ms |
| Throughput | 664.03 items/s | **108365.36 items/s** | 276.57 items/s |
| Binary Size | 2.1MB | **388KB** | 1.4MB |

**Insight:** Rust ชนะชัดเจนเพราะ `TcpStream::connect_timeout` + address parsing path มี overhead ต่ำมากสำหรับช่วงพอร์ตสั้นและ workload แบบ tight loop ขณะที่ Go/Zig ใช้เส้นทาง socket/connect ที่แพงกว่าในงานนี้ จึงเห็น throughput ต่างกันระดับ orders of magnitude.
