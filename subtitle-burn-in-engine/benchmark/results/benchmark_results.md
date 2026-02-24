# Subtitle Burn-in Engine — Benchmark Results

**Date**: 2026-02-25  
**Input**: `test-data/video.mp4` (640x360, 30s, 25fps)  
**Subtitle**: `test-data/subs.srt`  
**Machine**: macOS (Apple Silicon ARM64)  
**Runs**: 5 (1 warm-up, 4 measured)

## Performance

| Language | Avg (ms) | Min (ms) | Max (ms) | Peak Memory |
|----------|----------|----------|----------|-------------|
| **Go**   | 503      | 449      | 633      | 103,920 KB  |
| **Rust** | 419      | 399      | 473      | 104,000 KB  |
| **Zig**  | 392      | 390      | 394      | 101,120 KB  |

## Binary Size

| Language | Size  |
|----------|-------|
| Go       | 2.7M  |
| Rust     | 1.6M  |
| Zig      | 288K  |

## Code Lines

| Language | Lines |
|----------|-------|
| Go       | 340   |
| Rust     | 230   |
| Zig      | 332   |
