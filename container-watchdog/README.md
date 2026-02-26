# Container Watchdog

Container Watchdog จำลองการเฝ้าดู metrics ของ container แล้วตัดสินใจ trigger action ตาม policy (CPU/MEM thresholds + cooldown) เพื่อเปรียบเทียบ performance ของ Go / Rust / Zig

## วัตถุประสงค์

- วัด throughput ของ event loop ที่ใช้ policy decision ต่อ sample
- เปรียบเทียบ trade-off ของ Go / Rust / Zig ในงาน sidecar agent
- เน้น benchmark แบบ Docker-only ให้เงื่อนไขเทียบกันได้

## โครงสร้าง

```text
container-watchdog/
├── go/
├── rust/
├── zig/
├── test-data/
├── benchmark/
└── README.md
```

## สถิติ output มาตรฐาน

```text
--- Statistics ---
Total processed: <N>
Processing time: <X.XXX>s
Average latency: <X.XXX>ms
Throughput: <X.XX> items/sec
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผล benchmark จะถูกบันทึกที่ `benchmark/results/container_watchdog_<timestamp>.txt`

## ผลการวัด (Benchmark Results)

อ้างอิงไฟล์: `benchmark/results/container_watchdog_20260226_220632.txt`

```text
─ Go ─────────────────────
  Avg: 394962829.92 items/sec
  Min: 270906499 items/sec
  Max: 719887689 items/sec

─ Rust ─────────────────────
  Avg: 577372485.14 items/sec
  Min: 450877977 items/sec
  Max: 686360966 items/sec

─ Zig ─────────────────────
  Avg: 513348669.22 items/sec
  Min: 284710360 items/sec
  Max: 729859145 items/sec

─ Binary Size ───────────────
  Go: 1.50MB
  Rust: 388.00KB
  Zig: 2.28MB
```

## สรุปเปรียบเทียบ

| Metric | Go | Rust | Zig |
|---|---:|---:|---:|
| Throughput (avg) | 394,962,829.92 items/s | **577,372,485.14 items/s** | 513,348,669.22 items/s |
| Binary size | 1.50MB | **388KB** | 2.28MB |

**Key insight:** รอบนี้ Rust ทำ throughput สูงสุดพร้อมได้ binary เล็กสุด เหมาะกับงาน agent ที่ต้องการทั้งความเร็วและ footprint ต่ำ
