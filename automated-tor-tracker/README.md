# Automated TOR Tracker: Go vs Rust vs Zig

โปรเจกต์นี้จำลองการดึงข้อมูล TOR (Terms of Reference) เป็นข้อความหลายบรรทัด แล้วจัดหมวดสถานะงาน (done/in_progress/blocked/todo)

## โครงสร้าง

```text
automated-tor-tracker/
├── go/
├── rust/
├── zig/
├── test-data/
│   └── tor.txt
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
`benchmark/results/automated-tor-tracker_20260227_000358.txt`

```
── Go
  Avg: 44ms  |  Min: 42ms  |  Max: 47ms
  Throughput: 4742942.48 items/sec

── Rust
  Avg: 35ms  |  Min: 30ms  |  Max: 44ms
  Throughput: 6755853.39 items/sec

── Zig
  Avg: 12ms  |  Min: 11ms  |  Max: 13ms
  Throughput: 15810536.65 items/sec
```

### Summary

| Metric | Go | Rust | Zig |
|---|---:|---:|---:|
| Avg Time | 44ms | 35ms | **12ms** |
| Throughput | 4742942.48 items/s | 6755853.39 items/s | **15810536.65 items/s** |
| Binary Size | 1.6MB | **388KB** | 2.2MB |

**Insight:** Zig เร็วสุดชัดเจนในงาน text classification loop ที่ simple และ tight.
