---
trigger: always_on
---
# Code Refactor Patterns — Go / Rust / Zig

> โครงสร้างไดเรกทอรี, Dockerfile, benchmark script, statistics format → ดู **CLAUDE.md**

---

## Shared Patterns (ทุกภาษา)

1. **`main()` orchestrates only** — read args → config → init → run → print stats
2. **Stats struct แยกออกมาเสมอ** — มี method `avgLatencyMs()` / `throughput()`
   ไม่ใช้ closure-captured mutable variables
3. **Helper functions แยกชัดเจน** — `printConfig()`, `printStats()`, domain logic ต่างหาก
4. **ไม่คำนวณ inline ซ้ำๆ** — wrap ใน helper function เสมอ

---

## Go

```go
// ใช้ integer milliseconds — ป้องกัน time.Duration float truncation
const chunkDurationMs = 25

func chunkSamples(durationMs int) int {
    return sampleRate * durationMs / 1000
}

// startProcessor คืน channel แทนการใช้ closure capture
func (ac *AudioChunker) startProcessor() <-chan Stats { ... }
```

- method names: **lowercase** (unexported) — `newAudioChunker`, `processAudio`, `printStats`
- error wrapping: `fmt.Errorf("context: %w", err)` เสมอ
- integer ms arithmetic แทน `time.Duration.Seconds()` เมื่อคำนวณ samples/bytes

---

## Rust

```rust
// constants เป็น u64 ms — ป้องกัน Duration::as_secs() truncation bug
const CHUNK_DURATION_MS: u64 = 25;

fn bytes_for_ms(duration_ms: u64) -> usize { ... }

// processor เป็น free function คืน JoinHandle<Stats>
fn start_processor(receiver: mpsc::Receiver<Chunk>) -> thread::JoinHandle<Stats> { ... }

// sender.send() ใช้ .is_err() — ไม่ใช้ .unwrap()
if self.sender.send(chunk).is_err() { break; }
```

- ลบ empty methods ออก (เช่น `fn finalize() {}`)
- error messages ใน `map_err`: `format!("context: {}", e)`

---

## Zig

```zig
// constants เป็น ms + precompute ns สำหรับ sleep
const INTERVAL_MS = 10;
const INTERVAL_NS = INTERVAL_MS * std.time.ns_per_ms;

fn bytesForMs(duration_ms: usize) usize { ... }

// Chunk ไม่เก็บ allocator — stack value ส่งผ่าน callback
const Chunk = struct { data: []const u8, index: usize };

// overlap-safe buffer shift
std.mem.copyForwards(u8, dst, src);

// Stats struct มี methods
const Stats = struct {
    fn avgLatencyMs(self: Stats) f64 { ... }
    fn throughput(self: Stats, elapsed_ns: u64) f64 { ... }
};
```

- `std.debug.print` → stderr — benchmark script ต้องใช้ `2>&1`
- `std.mem.copyForwards` ป้องกัน overlapping memory ใน buffer shift
- `std.Thread.sleep` (ไม่ใช่ `std.time.sleep` — ไม่มีใน 0.15)
