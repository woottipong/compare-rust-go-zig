---
description: Compare Rust / Go / Zig — Mandatory project rules for all AI assistants
trigger: always_on
---

# Project Rules: Compare Rust / Go / Zig

## ⚠️ MANDATORY: Benchmark ต้องรันผ่าน Docker เสมอ

- `benchmark/run.sh` ต้องใช้ **Docker** — build image ก่อนแล้วค่อยรัน container
- ห้าม benchmark ด้วย local binary โดยตรง (local dev ยกเว้น)
- ก่อนรัน benchmark ตรวจสอบ Docker daemon: `docker info`
- image naming: `<prefix>-go`, `<prefix>-rust`, `<prefix>-zig`
- mount test-data: `-v "$INPUT_DIR":/data:ro`
- capture stdout+stderr: `2>&1` (Zig ใช้ stderr)
- parse output: `awk -F': ' '{print $2}'`
- บันทึกผล: `benchmark/results/<project>_<timestamp>.txt` เสมอ

---

## ⚠️ MANDATORY: Code Patterns ทุกโปรเจกต์ใหม่ต้องทำตามนี้

### Shared Patterns (ทุกภาษา)

1. **Helper function สำหรับ duration → bytes** — ไม่คำนวณ inline ซ้ำๆ
   - Go: `func bytesForMs(durationMs int) int`
   - Rust: `fn bytes_for_ms(duration_ms: u64) -> usize`
   - Zig: `fn bytesForMs(duration_ms: usize) usize`

2. **Stats struct แยกออกมาเสมอ** — ไม่ใช้ closure-captured mutable variables
   - มี method `avgLatencyMs()` และ `throughput()`

3. **แยก helper functions**: `printConfig(...)`, `printStats(...)`, domain logic ออกจาก `main()`

4. **`main()` ต้องกระชับ** — orchestrate เท่านั้น: read → config → init → run → stats → print

### Statistics Output Format (ทุกภาษาต้องตรงกัน)

```
--- Statistics ---
Total chunks: <N>
Processing time: <X.XXX>s
Average latency: <X.XXX>ms
Throughput: <X.XX> chunks/sec
```

### Go Patterns

```go
// ใช้ integer ms constants — ไม่ใช้ Duration.Seconds() สำหรับคำนวณ samples
const chunkDurationMs = 25

func chunkSamples(durationMs int) int { return sampleRate * durationMs / 1000 }

// startProcessor คืน channel แทน closure-captured vars
func (ac *AudioChunker) startProcessor() <-chan Stats { ... }
```

- method names: **lowercase** (unexported) เสมอ
- error wrapping: `fmt.Errorf("context: %w", err)`

### Rust Patterns

```rust
// constants เป็น u64 ms — ไม่ใช้ Duration::from_millis() ในการคำนวณ samples
const CHUNK_DURATION_MS: u64 = 25;

fn bytes_for_ms(duration_ms: u64) -> usize { ... }

// processor เป็น free function คืน JoinHandle<Stats>
fn start_processor(receiver: mpsc::Receiver<AudioChunk>) -> thread::JoinHandle<Stats> { ... }

// ไม่ใช้ .unwrap() บน send — ใช้ .is_err() แทน
if self.sender.send(chunk).is_err() { break; }
```

- ลบ empty methods ออก (เช่น `fn finalize() {}`)

### Zig Patterns

```zig
// constants เป็น ms + precompute ns สำหรับ sleep
const INPUT_INTERVAL_MS = 10;
const INPUT_INTERVAL_NS = INPUT_INTERVAL_MS * std.time.ns_per_ms;

// AudioChunk ไม่เก็บ allocator ใน struct — เป็น stack value
const AudioChunk = struct { data: []const u8, timestamp: std.time.Instant, index: usize };

// overlap buffer shift ใช้ std.mem.copyForwards (ป้องกัน overlapping memory bug)
std.mem.copyForwards(u8, dst_slice, src_slice);

// Stats มี methods
const Stats = struct {
    fn avgLatencyMs(self: Stats) f64 { ... }
    fn throughput(self: Stats, processing_ns: u64) f64 { ... }
};
```

### Vector DB Ingester Patterns

```zig
// Document processing with proper error handling
fn processContent(allocator: std.mem.Allocator, content: []const u8) !struct { count: usize } {
    var chunk_count: usize = 0;
    
    var chunk_words = std.ArrayList([]const u8).initCapacity(allocator, 1024) catch {
        return error.OutOfMemory;
    };
    defer chunk_words.deinit(allocator);
    
    // Process chunks with proper error handling
    const chunk_content = std.mem.join(allocator, " ", chunk_words.items) catch {
        return error.OutOfMemory;
    };
    defer allocator.free(chunk_content);
    
    return .{ .count = chunk_count };
}

// Embedding simulation (same algorithm across languages)
fn generateEmbedding(content: []const u8) [EMBEDDING_DIM]f32 {
    var embedding: [EMBEDDING_DIM]f32 = undefined;
    const hash = hashString(content);
    
    for (0..EMBEDDING_DIM) |i| {
        // Generate pseudo-random values based on hash
        var seed = hash ^ @as(u64, @intCast(i));
        // ... hash calculations ...
        embedding[i] = (@as(f32, @floatFromInt(seed & 0x7fffffff)) / @as(f32, @floatFromInt(std.math.maxInt(u32))) * 2.0 - 1.0;
    }
    return embedding;
}
```

### Benchmark Methodology

```bash
# 5 runs total: 1 warm-up + 4 measured
RUNS=5
WARMUP=1

run_benchmark() {
    local times=()
    
    for i in $(seq 1 $RUNS); do
        start=$(date +%s%N)
        # Run benchmark
        if docker run ...; then
            end=$(date +%s%N)
            elapsed=$(( (end - start) / 1000000 ))
            
            if [ "$i" -le "$WARMUP" ]; then
                echo "  Run $i (warm-up): ${elapsed}ms"
            else
                echo "  Run $i           : ${elapsed}ms"
                times+=("$elapsed")
            fi
        fi
    done
    
    # Calculate statistics
    if [ ${#times[@]} -gt 0 ]; then
        local total=0 min=${times[0]} max=${times[0]}
        for t in "${times[@]}"; do
            total=$((total + t))
            [ "$t" -lt "$min" ] && min=$t
            [ "$t" -gt "$max" ] && max=$t
        done
        echo "  Avg: $((total / ${#times[@]}))ms | Min: ${min}ms | Max: ${max}ms"
    fi
}
```

---

## โครงสร้างมาตรฐาน

```
<project-name>/
├── go/main.go + go.mod + Dockerfile
├── rust/src/main.rs + Cargo.toml + Dockerfile
├── zig/src/main.zig + build.zig + Dockerfile
├── test-data/           # gitignored — generate ด้วย ffmpeg
├── benchmark/run.sh     # Docker-based เสมอ
└── README.md            # ต้องมีตาราง comparison + ผลจริงจาก Docker benchmark
```

---

## Docker Image Naming

| Project | Go | Rust | Zig |
|---------|-----|------|-----|
| video-frame-extractor | `vfe-go` | `vfe-rust` | `vfe-zig` |
| hls-stream-segmenter | `hls-go` | `hls-rust` | `hls-zig` |
| subtitle-burn-in-engine | `sbe-go` | `sbe-rust` | `sbe-zig` |
| lightweight-api-gateway | `gw-go` | `gw-rust` | `gw-zig` |
| realtime-audio-chunker | `rac-go` | `rac-rust` | `rac-zig` |
| **vector-db-ingester** | **`vdi-go`** | **`vdi-rust`** | **`vdi-zig`** |

---

## Dockerfile Standards

### Go
- `CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w'` → static binary
- `mkdir -p /out` ก่อน build เสมอ

### Rust
- Builder: `rust:<version>-bookworm`
- dependency cache layer ก่อน copy real source
- `strip target/release/<binary>` หลัง build

### Zig
- Builder: `debian:bookworm-slim` + wget Zig tarball
- `ARG TARGETARCH`: `arm64` → `aarch64`, else → `x86_64`
- URL format (0.15+): `zig-${ZIG_ARCH}-linux-<ver>.tar.xz`

### Go + FFmpeg (CGO)
- ใช้ **Alpine** เท่านั้น (`golang:1.2x-alpine`) — bookworm arm64 มี `C.SwsContext` issue

### FFmpeg runtime packages (bookworm arm64)
`libavformat59`, `libavcodec59`, `libavutil57`, `libswscale6`, `libavfilter8`

---

## Known Bugs / Gotchas

| ภาษา | Bug | Fix |
|------|-----|-----|
| **Rust** | `Duration::as_secs()` truncates sub-second duration → samples = 0 | ใช้ `as_millis() / 1000` หรือ integer ms constants |
| **Zig** | `AudioChunk` เก็บ `allocator` ใน struct → ต้อง manage lifecycle ซับซ้อน | ใช้ stack value + ส่ง allocator ผ่าน `deinit(allocator)` |
| **Zig** | loop shift buffer ด้วย index อาจ overlap | ใช้ `std.mem.copyForwards` เสมอ |
| **Go** | `time.Duration.Seconds()` คืน float → int truncation สำหรับ < 1s | ใช้ integer ms arithmetic |
| **Zig** | `std.debug.print` → stderr ไม่ใช่ stdout | benchmark script ต้อง `2>&1` |

---

## benchmark/run.sh Standards

### Non-HTTP Projects (Audio, FFmpeg, CLI)
```bash
# build images ก่อนเสมอ
docker build -q -t "$tag" "$ctx"

# รัน + capture stdout+stderr
output=$(docker run --rm -v "$INPUT_DIR":/data:ro "$image" "/data/$INPUT_FILE" 2>&1)

# parse ด้วย awk ไม่ใช่ sed
avg=$(echo "$output" | grep "Average latency:" | awk -F': ' '{print $2}')

# binary size
cid=$(docker create "$image")
size=$(docker cp "$cid:/usr/local/bin/<binary>" - | wc -c)
docker rm "$cid"
```

### HTTP Throughput Projects
- `wrk -t4 -c50 -d3s` + Docker network
- cleanup `docker network rm` เสมอ

### ทั้งสอง
- `SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`
- auto-save: `exec > >(tee -a "$RESULT_FILE")`
