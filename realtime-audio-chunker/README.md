# Real-time Audio Chunker: Go vs Rust vs Zig

ระบบแบ่งไฟล์เสียงเป็น chunk ย่อยๆ สำหรับการประมวลผลแบบ Real-time (เช่น ส่งให้ ASR หรือ LLM) โดยจำลองการรับข้อมูลแบบ Real-time และวัด Latency/Throughput ของแต่ละภาษา

## วัตถุประสงค์
- ฝึกการจัดการ Buffer สำหรับข้อมูล Audio (เช่น Circular Buffer, Overlapping)
- ฝึกใช้งาน Concurrency model (Go: Goroutines, Rust: Tokio/Threads, Zig: Manual loops)
- เปรียบเทียบ Latency ในการประมวลผล Chunk ของแต่ละภาษา

## โครงสร้าง
```
realtime-audio-chunker/
├── go/                 # Go implementation
│   ├── main.go         # ใช้ Goroutines และ Channels
│   └── Dockerfile
├── rust/               # Rust implementation
│   ├── src/main.rs     # ใช้ mpsc channels และ Threads
│   ├── Cargo.toml
│   └── Dockerfile
├── zig/                # Zig implementation
│   ├── src/main.zig    # จัดการ Memory และ Buffer เอง
│   ├── build.zig
│   └── Dockerfile
├── test-data/          # ไฟล์เสียงสำหรับทดสอบ
│   └── sample.wav      # (Generate ด้วย FFmpeg)
└── benchmark/
    └── run.sh          # Script วัดผล
```

## Dependencies
- ไม่มีการใช้ Library ภายนอกสำหรับการจัดการ Audio (อ่าน WAV header และ PCM data โดยตรง)
- **Rust**: ไม่ต้องใช้ external crates เพราะใช้ thread/mpsc ของ standard library

## Build & Run

### สร้าง Test Data (WAV)
```bash
ffmpeg -f lavfi -i sine=frequency=440:duration=10 -ar 16000 -ac 1 -c:a pcm_s16le test-data/sample.wav
```

### Go
```bash
cd go
go build -o ../bin/realtime-audio-chunker-go .
../bin/realtime-audio-chunker-go ../test-data/sample.wav
```

### Rust
```bash
cd rust
cargo build --release
../rust/target/release/realtime-audio-chunker ../test-data/sample.wav
```

### Zig
```bash
cd zig
zig build -Doptimize=ReleaseFast
./zig-out/bin/realtime-audio-chunker ../test-data/sample.wav
```

## Docker Build & Run

### Build Images
```bash
# Build all images
docker build -t rac-go   go/
docker build -t rac-rust rust/
docker build -t rac-zig  zig/
```

### Docker Run
```bash
# Create test data first
ffmpeg -f lavfi -i sine=frequency=440:duration=10 -ar 16000 -ac 1 -c:a pcm_s16le test-data/sample.wav

# Run with test data
docker run --rm -v "$(pwd)/test-data:/data:ro" rac-go /data/sample.wav
docker run --rm -v "$(pwd)/test-data:/data:ro" rac-rust /data/sample.wav
docker run --rm -v "$(pwd)/test-data:/data:ro" rac-zig /data/sample.wav
```

## Benchmark

```bash
bash benchmark/run.sh
```

ผลลัพธ์จะถูก save อัตโนมัติลง `benchmark/results/realtime-audio-chunker_YYYYMMDD_HHMMSS.txt`

*(หมายเหตุ: รัน 5 ครั้ง: 1 warm-up + 4 วัดผล — ใช้เวลา ~50-60 วินาที เพราะจำลอง real-time audio 10s ต่อรอบ)*

## Benchmark Results

```
╔══════════════════════════════════════════╗
║    Real-time Audio Chunker Benchmark     ║
╚══════════════════════════════════════════╝
  Input    : test-data/sample.wav
  Runs     : 5 (1 warm-up + 4 measured)
  Mode     : Docker

── Go   ───────────────────────────────────────
  Run 1 (warm-up): 11524ms
  Run 2           : 11521ms
  Run 3           : 11519ms
  Run 4           : 11522ms
  Run 5           : 11523ms
  ─────────────────────────────────────────
  Avg: 11521ms  |  Min: 11519ms  |  Max: 11523ms

  Total Chunks : 666
  Avg Latency  : 0.006 ms
  Throughput   : 57.81 chunks/sec

── Rust ───────────────────────────────────────
  Run 1 (warm-up): 12215ms
  Run 2           : 12208ms
  Run 3           : 12210ms
  Run 4           : 12207ms
  Run 5           : 12208ms
  ─────────────────────────────────────────
  Avg: 12208ms  |  Min: 12207ms  |  Max: 12210ms

  Total Chunks : 666
  Avg Latency  : 0.061 ms
  Throughput   : 54.56 chunks/sec

── Zig  ───────────────────────────────────────
  Run 1 (warm-up): 12142ms
  Run 2           : 12138ms
  Run 3           : 12136ms
  Run 4           : 12139ms
  Run 5           : 12140ms
  ─────────────────────────────────────────
  Avg: 12138ms  |  Min: 12136ms  |  Max: 12140ms

  Total Chunks : 666
  Avg Latency  : 0.000 ms
  Throughput   : 54.87 chunks/sec

── Binary Size ───────────────────────────────
  Go  : 1.5MB
  Rust: 452KB
  Zig : 2.2MB

── Code Lines ────────────────────────────────
  Go  : 198 lines
  Rust: 180 lines
  Zig : 157 lines
```

**Key insight**: Throughput ใกล้เคียงกันทุกภาษา เพราะ bottleneck คือ real-time audio simulation (10s input = ~10s process) ไม่ใช่ความเร็วภาษา — แต่ **latency ต่างกันชัดเจน** และเผยให้เห็น runtime overhead ของแต่ละภาษา:

- **Zig: 0.000 ms** (< 0.5 µs จริง, ~17 ns) — ใช้ synchronous callback loop โดยตรง ไม่มี channel, ไม่มี scheduler ทุก chunk ถูก process ทันทีใน same goroutine/thread
- **Go: 0.006 ms (~6 µs)** — goroutine scheduling + channel `send`/`receive` มี overhead แม้จะเร็วมากเมื่อเทียบกับ context switch จริง
- **Rust: 0.061 ms (~61 µs)** — `mpsc` channel + thread synchronization มี overhead สูงกว่า เพราะ cross-thread message passing ต้องผ่าน atomic operation

**บทเรียน**: สำหรับ hot-path synchronous loop ที่ไม่ต้องการ true concurrency (เช่น audio chunk processing แบบ sequential) Zig's direct callback ชนะ channel-based architecture ทุกภาษาอย่างชัดเจน — ถ้าเพิ่ม concurrency เข้ามา (เช่น process หลาย audio stream พร้อมกัน) ผลอาจกลับกัน

### Summary

## ตารางเปรียบเทียบ (Docker Benchmark — sample.wav 10s, 16kHz mono)

| Aspect | Go | Rust | Zig |
|--------|-----|------|-----|
| **Total Chunks** | 666 | 666 | 666 |
| **Avg Latency** | 0.006 ms | 0.061 ms | 0.000 ms |
| **Throughput (chunks/s)** | 57.81 | 54.56 | 54.87 |
| **Processing Time** | 11.521 s | 12.208 s | 12.138 s |
| **Binary Size** | 1.5 MB | 452 KB | 2.2 MB |
| **Code Lines** | 198 | 180 | 157 |
| **Memory Model** | Garbage Collected | Ownership / RAII | Manual (GPA) |

## หมายเหตุ / บทเรียน
1. **Buffer Management**: การทำ Overlapping chunks ต้องระวังเรื่องการ shift array ซึ่งใน Go ใช้ `copy()`, Rust ใช้ `copy_within()`, และ Zig ต้องเขียน loop เองเนื่องจาก memory overlap
2. **Timing & Latency**:
   - Go มี `time.Since()` ที่ใช้งานง่าย
   - Rust ใช้ `std::time::Instant::elapsed()`
   - Zig ใช้ `std.time.Instant.now() catch ...` ซึ่งต้องระวังเรื่อง error handling กับ hardware clock ที่อาจไม่รองรับ
3. **Architecture**:
   - Go/Rust ใช้ Channel / MPSC เพื่อแยก thread การรับข้อมูลและการประมวลผล
   - Zig ออกแบบเป็น Context / Callback function เพื่อหลีกเลี่ยง overhead ของ threading ถ้าระบบไม่ได้ซับซ้อนมาก
