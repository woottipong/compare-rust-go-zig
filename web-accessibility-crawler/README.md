# Web Accessibility Crawler: Go vs Rust vs Zig

โปรเจกต์นี้จำลองการ crawl/scan หน้าเว็บ HTML เพื่อหาปัญหา accessibility เบื้องต้น (missing title/lang, img without alt, link without aria-label)

## โครงสร้าง

```text
web-accessibility-crawler/
├── go/
├── rust/
├── zig/
├── test-data/
│   └── pages.html
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
`benchmark/results/web-accessibility-crawler_20260227_000148.txt`

```
── Go
  Avg: 385ms  |  Min: 373ms  |  Max: 401ms
  Throughput: 1339629.74 items/sec

── Rust
  Avg: 118ms  |  Min: 117ms  |  Max: 121ms
  Throughput: 4237099.62 items/sec

── Zig
  Avg: 139ms  |  Min: 139ms  |  Max: 140ms
  Throughput: 3606971.18 items/sec
```

### Summary

| Metric | Go | Rust | Zig |
|---|---:|---:|---:|
| Avg Time | 385ms | **118ms** | 139ms |
| Throughput | 1339629.74 items/s | **4237099.62 items/s** | 3606971.18 items/s |
| Binary Size | 1.7MB | **388KB** | 2.2MB |

**Insight:** Rust เร็วสุดในงาน parse/check string-heavy แบบนี้ และยังมี binary เล็กสุด.
