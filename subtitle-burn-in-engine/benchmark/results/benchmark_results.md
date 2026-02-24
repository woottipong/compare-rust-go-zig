# Subtitle Burn-in Engine — Benchmark Results

**Date**: 2026-02-25  
**Input**: `test-data/video.mp4` (640x360, 30s, 25fps)  
**Subtitle**: `test-data/subs.srt`  
**Machine**: macOS (Apple Silicon ARM64)  
**Runs**: 5 (1 warm-up, 4 measured)

## Performance

| Language | Avg (ms) | Min (ms) | Max (ms) | Peak Memory |
|----------|----------|----------|----------|-------------|
| **Go**   | 463      | 446      | 478      | 103,856 KB  |
| **Rust** | 503      | 467      | 574      | 103,904 KB  |
| **Zig**  | 431      | 424      | 448      | 101,024 KB  |

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
