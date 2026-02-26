# Custom BitTorrent Client: Go vs Rust vs Zig

โปรเจกต์นี้จำลอง BitTorrent handshake (TCP) กับ mock peer เพื่อเปรียบเทียบประสิทธิภาพด้าน binary protocol และ network socket ของ Go, Rust, Zig

## โครงสร้าง

```text
custom-bittorrent-client/
├── go/
├── rust/
├── zig/
├── test-data/
│   ├── mock_peer.py
│   └── Dockerfile
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
`benchmark/results/custom-bittorrent-client_20260226_235246.txt`

```
── Go
  Avg: 594ms  |  Min: 585ms  |  Max: 619ms
  Throughput: 3404.84 items/sec

── Rust
  Avg: 410ms  |  Min: 405ms  |  Max: 416ms
  Throughput: 4880.07 items/sec

── Zig
  Avg: 388ms  |  Min: 372ms  |  Max: 403ms
  Throughput: 5382.10 items/sec
```

### Summary

| Metric | Go | Rust | Zig |
|---|---:|---:|---:|
| Avg Time | 594ms | 410ms | **388ms** |
| Throughput | 3404.84 items/s | 4880.07 items/s | **5382.10 items/s** |
| Binary Size | 2.2MB | **388KB** | 1.4MB |

**Insight:** Zig throughput สูงสุด, Rust ตามมาติดๆ และได้ binary เล็กสุด.
