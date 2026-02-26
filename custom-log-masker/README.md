# Custom Log Masker

กรองข้อมูล Sensitive (PII) ออกจาก Log ด้วยความเร็วสูง — รองรับ streaming ไฟล์ขนาดใหญ่โดยไม่โหลดทั้งหมดใน memory

---

## วัตถุประสงค์

- ฝึก String Processing และ Pattern Matching ที่มีประสิทธิภาพ
- เปรียบเทียบ Regex (Go/Rust) vs Manual Pattern Matching (Zig)
- วัด Throughput (MB/s) ในการประมวลผล log streaming

---

## โครงสร้าง

```
custom-log-masker/
├── go/
│   ├── main.go         # regex-based masking
│   ├── go.mod
│   └── Dockerfile
├── rust/
│   ├── src/
│   │   └── main.rs     # regex crate
│   ├── Cargo.toml
│   └── Dockerfile
├── zig/
│   ├── src/
│   │   └── main.zig    # manual pattern matching
│   ├── build.zig
│   └── Dockerfile
├── test-data/
│   ├── sample.log      # 15 lines sample
│   └── large.log       # ~100K lines (auto-generated)
├── benchmark/
│   ├── results/
│   └── run.sh          # Docker-based benchmark
└── README.md
```

---

## Masking Rules

| Pattern | Example Input | Output |
|---------|---------------|--------|
| **Email** | `user@example.com` | `[EMAIL_MASKED]` |
| **Phone** | `+1 (555) 123-4567` | `[PHONE_MASKED]` |
| **Credit Card** | `4532015112830366` | `[CC_MASKED]` |
| **SSN** | `123-45-6789` | `[SSN_MASKED]` |
| **API Key** | `api_key=sk-1234...` | `[API_KEY_MASKED]` |
| **Password** | `password=secret123` | `[PASSWORD_MASKED]` |
| **IP Address** | `192.168.1.100` | `[IP_MASKED]` |

---

## Dependencies

- **Go**: `regexp` (stdlib)
- **Rust**: `regex = "1.11"`
- **Zig**: std library only (manual pattern matching)

---

## Build & Run

### Local Build

```bash
# Go
unset GOROOT && go build -o clm-go .
./clm-go --input sample.log --output masked.log

# Rust
cargo build --release
./target/release/custom-log-masker -i sample.log -o masked.log

# Zig
zig build -Doptimize=ReleaseFast
./zig-out/bin/custom-log-masker -i sample.log -o masked.log
```

### Docker Build

```bash
docker build -t clm-go   go/
docker build -t clm-rust rust/
docker build -t clm-zig  zig/
```

### Docker Run

```bash
# Mask log file
docker run --rm -v "$(pwd)/test-data:/data:ro" -v "$(pwd)/output:/out" clm-go \
  --input /data/sample.log --output /out/masked.log

# Stream from stdin
cat test-data/sample.log | docker run --rm -i clm-rust > masked.log
```

---

## Benchmark

```bash
cd custom-log-masker
bash benchmark/run.sh
```

---

## ผลการเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|-----|------|-----|
| **Throughput** | 3.91 MB/s | **41.71 MB/s** | 11.68 MB/s |
| **Lines/sec** | 52,280 | **557,891** | 156,234 |
| **Processing Time** | 1.913s | **0.179s** | 0.640s |
| **Binary Size** | **1.8MB** | 1.9MB | 2.2MB |
| **Code Lines** | 183 | **127** | 473 |

> **Test**: 100K lines (7.5MB) with 86,658 PII matches — Docker on macOS Apple Silicon

**Winner: Rust** — 10x faster than Go, 3.5x faster than Zig

---

## Benchmark Results

```
╔══════════════════════════════════════════╗
║     Custom Log Masker Benchmark          ║
╚══════════════════════════════════════════╝
── Test Data ──────────────────────────────────
  Input file: large.log
  Lines:    99990
  Size: 7.5MB
── Go   ───────────────────────────────────────
  Run 1 (warm-up): 2189ms
  Run 2           : 2200ms
  Run 3           : 2016ms
  Run 4           : 2147ms
  Run 5           : 1961ms
  Avg: 2081ms  |  Min: 1961ms  |  Max: 2200ms
  Lines processed : 99990
  Matches found   : 86658
  Throughput      : 3.81 MB/s
  Lines/sec       : 50981
── Rust ───────────────────────────────────────
  Run 1 (warm-up): 164ms
  Run 2           : 171ms
  Run 3           : 171ms
  Run 4           : 166ms
  Run 5           : 162ms
  Avg: 167ms  |  Min: 162ms  |  Max: 171ms
  Lines processed : 99990
  Matches found   : 86658
  Throughput      : 46.21 MB/s
  Lines/sec       : 618100
── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 831ms
  Run 2           : 659ms
  Run 3           : 664ms
  Run 4           : 706ms
  Run 5           : 662ms
  Avg: 672ms  |  Min: 659ms  |  Max: 706ms
  Lines processed : 99990
  Matches found   : 86658
  Throughput      : 11.29 MB/s
  Lines/sec       : 151042
── Binary Size ───────────────────────────────
  Go  : 1.8MB
  Rust: 1.9MB
  Zig : 2.2MB
── Code Lines ────────────────────────────────
  Go  : 183 lines
  Rust: 127 lines
  Zig : 473 lines
```

> **Test**: 100K lines (7.5MB) — 5 runs (1 warm-up + 4 measured) on Docker  
> **Results saved to**: `benchmark/results/custom-log-masker_20260225_233551.txt`

---

### Summary

## ตารางเปรียบเทียบ

| Aspect | Go | Rust | Zig |
|--------|-----|------|-----|
| **Pattern Matching** | `regexp.Regexp` | `regex::Regex` | Manual state machine |
| **Regex Engine** | RE2 (backtrack-free) | RE2-like | N/A (hand-coded) |
| **Streaming I/O** | `bufio.Reader/Writer` | `BufReader/BufWriter` | `bufferedReader/Writer` |
| **Buffer Size** | 64KB | 64KB | 8KB |
| **Memory Safety** | GC | Ownership | Manual |
| **Code Complexity** | ต่ำ (regex ทำงานให้) | ต่ำ (regex ทำงานให้) | สูง (manual matching) |

**Key insight:** งานนี้เป็น pattern-matching หนักและมี string replace จำนวนมาก ทำให้ Rust `regex` crate ได้ประโยชน์จาก optimized engine ชัดเจน (SIMD-friendly path + allocation control) จึงชนะ throughput แบบทิ้งระยะเหนือ Go และ Zig.

---

## หมายเหตุ

### Go — Regex-based
- ใช้ `regexp` package (RE2 engine) — ไม่ support backreference แต่ปลอดภัยจาก ReDoS
- จัดการ memory อัตโนมัติผ่าน GC
- Code อ่านง่าย, maintain ง่าย

### Rust — Regex with Zero-Copy
- `regex` crate มี performance ดีมาก (SIMD optimized)
- `BufReader`/`BufWriter` กับ buffer 64KB
- Zero-copy matching ถ้าไม่ต้อง replace

### Zig — Manual Pattern Matching
- ไม่ใช้ regex library — implement matching logic เองทั้งหมด
- เรียนรู้ algorithmic thinking: state machine, string scanning
- Trade-off: code เยอะกว่าแต่ไม่มี external dependency

---

## Key Lessons

| Lesson | Details |
|--------|---------|
| **Regex vs Manual** | Regex สะดวกแต่มี overhead, Manual เร็วกว่าแต่ code เยอะ |
| **Buffer Size** | 64KB คือ sweet spot สำหรับ log processing |
| **Streaming** | อย่าโหลดไฟล์ทั้งหมดใน memory — ใช้ buffered I/O |
| **Pattern Priority** | ต้องจัดการ overlapping matches (longest match first) |

---

## ตัวอย่าง Input/Output

**Input:**
```
2024-01-15 10:23:45 INFO User john.doe@example.com logged in from 192.168.1.100
2024-01-15 10:23:46 DEBUG API call with api_key=sk-1234567890abcdef
2024-01-15 10:23:47 ERROR Login failed for user with SSN 123-45-6789
```

**Output:**
```
2024-01-15 10:23:45 INFO User [EMAIL_MASKED] logged in from [IP_MASKED]
2024-01-15 10:23:46 DEBUG API call with [API_KEY_MASKED]
2024-01-15 10:23:47 ERROR Login failed for user with SSN [SSN_MASKED]
```
