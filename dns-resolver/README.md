# DNS Resolver: Go vs Rust vs Zig

โปรเจกต์นี้ทำ DNS A-record query ผ่าน raw UDP packet (build/parse DNS message เอง) และ benchmark throughput ของแต่ละภาษา

## โครงสร้าง

```text
dns-resolver/
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
│   └── mock_dns.py
├── benchmark/
│   ├── results/
│   └── run.sh
└── README.md
```

## Dependencies
- Docker
- Python 3 (mock DNS server ที่รันบน host)

## Build & Run

### Start mock DNS server (terminal 1)

```bash
python3 test-data/mock_dns.py
```

### Go

```bash
unset GOROOT && go build -o ../bin/dns-resolver-go .
../bin/dns-resolver-go host.docker.internal 53535 10000
```

### Rust

```bash
cargo build --release
./target/release/dns-resolver host.docker.internal 53535 10000
```

### Zig

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/dns-resolver host.docker.internal 53535 10000
```

## Benchmark

```bash
bash benchmark/run.sh
```

script จะ start mock DNS server อัตโนมัติ, รัน Docker container ทั้ง 3 (1 warm-up + 4 measured) แล้ว save ผลลัพธ์ลง `benchmark/results/dns-resolver_YYYYMMDD_HHMMSS.txt`

## Benchmark Results

วัดด้วย `REPEATS=10000` queries ต่อรอบ, mock DNS server (Python) บน host, Docker container query ผ่าน `host.docker.internal:53535`, Apple M-series

```text
╔══════════════════════════════════════════╗
║          DNS Resolver Benchmark          ║
╚══════════════════════════════════════════╝
  DNS      : host.docker.internal:53535
  Repeats  : 10000
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 1589ms
  Run 2           : 1564ms
  Run 3           : 1606ms
  Run 4           : 1578ms
  Run 5           : 1625ms
  ─────────────────────────────────────────
  Avg: 1593ms  |  Min: 1564ms  |  Max: 1625ms

  Total processed: 10000
  Processing time: 1.625s
  Average latency: 0.162493ms
  Throughput     : 6154.11 items/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 1498ms
  Run 2           : 1631ms
  Run 3           : 1570ms
  Run 4           : 1661ms
  Run 5           : 1655ms
  ─────────────────────────────────────────
  Avg: 1629ms  |  Min: 1570ms  |  Max: 1661ms

  Total processed: 10000
  Processing time: 1.655s
  Average latency: 0.165465ms
  Throughput     : 6043.59 items/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 1647ms
  Run 2           : 1756ms
  Run 3           : 1603ms
  Run 4           : 1632ms
  Run 5           : 1663ms
  ─────────────────────────────────────────
  Avg: 1663ms  |  Min: 1603ms  |  Max: 1756ms

  Total processed: 10000
  Processing time: 1.663s
  Average latency: 0.166290ms
  Throughput     : 6013.60 items/sec

── Binary Size ───────────────────────────────
  Go  : 2.1MB
  Rust: 388KB
  Zig : 1.4MB

── Code Lines ────────────────────────────────
  Go  : 185 lines
  Rust: 182 lines
  Zig : 198 lines
```

ผลลัพธ์ถูกบันทึกไว้ที่:
`benchmark/results/dns-resolver_20260227_015416.txt`

## ตารางเปรียบเทียบ

| Metric | Go | Rust | Zig |
|--------|----|------|-----|
| Avg time (4 measured runs) | **1,593ms** | 1,629ms | 1,663ms |
| Min/Max time | **1,564/1,625ms** | 1,570/1,661ms | 1,603/1,756ms |
| Avg latency/query | **0.162ms** | 0.165ms | 0.166ms |
| Throughput | **6,154 queries/sec** | 6,043 queries/sec | 6,013 queries/sec |
| Binary size | 2.1MB | **388KB** | 1.4MB |
| Code lines | 185 | **182** | 198 |

## Key Insights

1. **ผลทั้ง 3 ภาษาแทบเหมือนกัน** — Go 6,154, Rust 6,043, Zig 6,013 queries/sec ต่างกันไม่ถึง 3% เพราะ bottleneck คือ UDP round-trip latency (~0.16ms/query) ไม่ใช่ภาษา
2. **Go มี variance ต่ำสุด** (1,564–1,625ms, ~4%) ขณะที่ Zig สูงสุด (1,603–1,756ms, ~10%) จาก UDP jitter บน loopback
3. **Rust ชนะ binary size** อย่างชัดเจนที่ 388KB (เล็กกว่า Go 5.4×, เล็กกว่า Zig 3.6×)
4. **Zig ชนะ binary size เป็นอันดับ 2** ที่ 1.4MB แม้ใช้ cImport C socket API ซึ่งเป็น pattern ที่ไม่ต้องพึ่ง stdlib networking ของ Zig
5. **Go มี code น้อยกว่า Zig** (185 vs 198 lines) เพราะ `net.DialTimeout` + `net.Conn` ซ่อน socket details ขณะ Zig ต้องเรียก `getaddrinfo` + `sendto`/`recvfrom` โดยตรง
6. **งานนี้วัด UDP I/O loop latency** ไม่ใช่ algorithm — เหมาะสำหรับเปรียบเทียบ socket API overhead ของแต่ละภาษา

## Technical Notes

- **Mock DNS server**: Python single-threaded UDP server (`mock_dns.py`) รันบน host port 53535, ตอบทุก query ด้วย A record `93.184.216.34` (example.com)
- **Pipeline per query**: build DNS wire-format query → UDP send → UDP recv → parse DNS response → count A records
- **Timing scope**: timer ครอบ REPEATS × (build_query + sendto + recvfrom + parse) — dominated by UDP kernel round-trip
- **Go**: `net.Conn` (UDP) + `conn.Write/Read` — stdlib wraps syscalls cleanly; `buildQuery` allocates per call
- **Rust**: `UdpSocket::bind` + `connect` + `send/recv` — stack-allocated recv buf `[0u8; 512]`; per-query `Vec<u8>` for outgoing query
- **Zig**: raw C socket API via `@cImport` — `getaddrinfo` + `sendto`/`recvfrom`; `buildQuery` allocs GPA per call with `ArrayList`
