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

## Benchmark
วัดผลด้วย `benchmark/run.sh` ซึ่งจะสร้าง Docker container และประมวลผลไฟล์ `sample.wav` โดยจำลองเวลาจริง (10 วินาที)

```bash
bash benchmark/run.sh
```

*(หมายเหตุ: ต้องเปิด Docker Daemon ไว้เพื่อรัน Benchmark)*

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
