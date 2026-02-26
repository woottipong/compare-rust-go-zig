# Sheets-to-DB Sync: Go vs Rust vs Zig

โปรเจกต์นี้จำลองการ sync ข้อมูลจาก Google Sheets (CSV) ลงฐานข้อมูล (CSV snapshot) โดยวัดประสิทธิภาพการ upsert ใน memory map

## โครงสร้าง

```text
sheets-to-db-sync/
├── go/
├── rust/
├── zig/
├── test-data/
│   ├── sheet.csv
│   └── db.csv
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
`benchmark/results/sheets-to-db-sync_20260226_235647.txt`

```
── Go
  Avg: 60ms  |  Min: 57ms  |  Max: 69ms
  Throughput: 69121537.66 items/sec

── Rust
  Avg: 555ms  |  Min: 552ms  |  Max: 559ms
  Throughput: 7248737.25 items/sec

── Zig
  Avg: 53ms  |  Min: 53ms  |  Max: 54ms
  Throughput: 73838600.04 items/sec
```

### Summary

| Metric | Go | Rust | Zig |
|---|---:|---:|---:|
| Avg Time | 60ms | 555ms | **53ms** |
| Throughput | 69121537.66 items/s | 7248737.25 items/s | **73838600.04 items/s** |
| Binary Size | 1.6MB | **388KB** | 2.2MB |

**Insight:** Zig เร็วสุดเล็กน้อย และ Go ตามมาติดๆ ขณะที่ Rust ช้ากว่าใน workload ที่ต้อง clone ข้อมูลบ่อย.
