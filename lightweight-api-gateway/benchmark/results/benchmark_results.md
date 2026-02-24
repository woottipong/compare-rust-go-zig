# Lightweight API Gateway — Benchmark Results

**Date**: 2026-02-25  
**Input**: Mock backend on localhost:3000  
**Gateway Port**: 8080  
**Machine**: macOS (Apple Silicon ARM64)  
**Runs**: 5 (1 warm-up, 4 measured)

## Performance (wrk: 4 threads, 50 connections, 3s duration)

| Language | Avg (req/s) | Min | Max | Peak Memory |
|----------|-------------|-----|-----|-------------|
| **Go** (Fiber)     | 54,919 | 54,599 | 55,273 | 11,344 KB |
| **Rust** (axum)    | 57,056 | 54,727 | 57,835 | 2,528 KB  |
| **Zig** (Zap)      | 52,103 | 49,842 | 53,050 | 27,680 KB |
| **Zig** (manual)   | 8,599  | 8,492  | 8,784  | 1,360 KB  |

## Binary Size

| Language | Size  |
|----------|-------|
| Go       | 9.1M  |
| Rust     | 1.6M  |
| Zig      | 233K  |

## Code Lines

| Language | Lines |
|----------|-------|
| Go (Fiber)   | 209   |
| Rust (axum)  | 173   |
| Zig (Zap)    | 146   |
| Zig (manual) | 187   |

## Key Findings

1. **Rust (axum)** fastest — 57,056 req/s, lowest memory (2.5MB) — Tokio async I/O efficient
2. **Go (Fiber)** close second — 54,919 req/s (~4% ช้ากว่า Rust)
3. **Zig (Zap)** เร็วกว่า Go เล็กน้อยหลัง switch มาใช้ Zap — 52,103 req/s (เดิม 8,599 req/s)
4. **Zap เร็วกว่า manual Zig 6x** — เพราะ facil.io ใช้ async event loop + multi-threaded
5. **Zig Zap memory สูง** (27MB) เพราะ facil.io worker pool — trade-off กับ throughput
6. **Binary**: Zig 233KB (smallest), Rust 1.6MB, Go 9.1MB
7. ทุกภาษาอยู่ใน ballpark เดียวกันเมื่อใช้ framework ที่เหมาะสม (~50-57K req/s)
