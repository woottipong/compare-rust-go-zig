# Sheets-to-DB Sync: Go vs Rust vs Zig

จำลองการ sync ข้อมูลจาก Google Sheets (CSV) ลงฐานข้อมูล (CSV snapshot) โดย upsert ใน in-memory HashMap ซ้ำหลายรอบ เพื่อวัดความเร็วของ map insert + string handling

## โครงสร้าง

```text
sheets-to-db-sync/
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
│   ├── sheet.csv   # 20 rows (source)
│   └── db.csv      # 20 rows (target)
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies

- Docker (for benchmark)

## Build

```bash
# Go
unset GOROOT && go build -o ../bin/s2d-go ./go

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

อ้างอิงจาก: `benchmark/results/sheets-to-db-sync_20260227_131143.txt`

```
Dataset : 20 rows × 4 fields (id, name, email, updated_at)
Repeats : 2,000,000 sync cycles
Total   : 40,000,000 row upserts per language
```

| Run | Go | Rust | Zig |
|-----|---:|-----:|----:|
| Warm-up | 548ms | 6077ms | 509ms |
| Run 2 | 642ms | 5608ms | 501ms |
| Run 3 | 538ms | 5505ms | 510ms |
| Run 4 | 563ms | 5638ms | 503ms |
| Run 5 | 559ms | 5593ms | 500ms |
| **Avg** | **575ms** | **5,586ms** | **503ms** |
| Min | 538ms | 5,505ms | 500ms |
| Max | 642ms | 5,638ms | 510ms |

### Summary

| Metric | Go | Rust | Zig |
|--------|---:|-----:|----:|
| Avg Time | 575ms | 5,586ms | **503ms** |
| Throughput | 71.6M items/s | 7.2M items/s | **80.1M items/s** |
| Binary Size | 1.6MB | **388KB** | 2.2MB |
| Code Lines | 133 | **130** | 133 |

## Key Insight

**Zig ชนะเล็กน้อยเหนือ Go และทั้งคู่เร็วกว่า Rust ~10× — เพราะ string ownership ใน sync_rows()**

งานนี้เหมือนกับ in-memory-kv-store ทุกประการ — ต้นเหตุอยู่ที่ **map insert semantics**:

| ภาษา | `syncRows` insert | String copy cost |
|------|-------------------|------------------|
| **Zig** | `db_map.put(r.id, r)` — slice (ptr+len) | **ไม่มี** |
| **Go** | `db[r.id] = r` — struct copy (string header) | **ไม่มี** (header copy เท่านั้น) |
| **Rust** | `db_map.insert(r.id.clone(), r.clone())` | **4 heap alloc ต่อ row** |

- **Rust ช้า 10×**: `r.clone()` ต้องจัดสรร String ใหม่สำหรับทุก field (id, name, email, updated_at) × 20 rows × 2,000,000 repeats = **160 ล้าน heap allocations** ใน sync phase เพียงอย่างเดียว
- **Go ตรงกลาง**: string header copy (pointer+len+cap) ไม่ deep copy → GC track references แต่ไม่ allocate ใหม่
- **Zig เร็วสุด**: `[]const u8` slice ชี้เข้าของเดิม → zero allocation ใน put path

pattern เดียวกับ in-memory-kv-store: Rust ownership model ถูกต้อง แต่ต้องจ่ายค่า allocation สำหรับงานที่ต้องการ owned values ใน HashMap

**Rust binary เล็กสุด 388KB** — ไม่มี GC runtime
