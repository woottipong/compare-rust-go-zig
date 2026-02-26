# DNS Resolver: Go vs Rust vs Zig

โปรเจกต์นี้ทำ DNS A-record query ผ่าน raw UDP packet (build/parse DNS message เอง) และ benchmark throughput ของแต่ละภาษา

## โครงสร้าง

```text
dns-resolver/
├── go/
├── rust/
├── zig/
├── test-data/
│   └── mock_dns.py
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
`benchmark/results/dns-resolver_20260226_233433.txt`

```
── Go
  Avg: 341ms  |  Min: 334ms  |  Max: 363ms
  Throughput: 5963.27 items/sec

── Rust
  Avg: 318ms  |  Min: 314ms  |  Max: 325ms
  Throughput: 6155.18 items/sec

── Zig
  Avg: 396ms  |  Min: 349ms  |  Max: 447ms
  Throughput: 5492.31 items/sec
```

### Summary

| Metric | Go | Rust | Zig |
|---|---:|---:|---:|
| Avg Time | 341ms | **318ms** | 396ms |
| Throughput | 5963.27 items/s | **6155.18 items/s** | 5492.31 items/s |
| Binary Size | 2.1MB | **388KB** | 1.4MB |

**Insight:** Rust ชนะทั้ง latency และ throughput ใน workload นี้ และยังได้ binary เล็กสุด.
