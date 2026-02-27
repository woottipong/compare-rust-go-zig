---
trigger: always_on
---
# Project Rules: Compare Rust / Go / Zig

> Dockerfile templates, Known Bugs, Statistics format, Benchmark methodology → ดู **CLAUDE.md** (single source of truth)

---

## ⚠️ Checklist สำหรับ Project ใหม่ทุกตัว

ก่อน implement ต้องมีครบทุกข้อ:

- [ ] โครงสร้าง `go/`, `rust/`, `zig/`, `test-data/`, `benchmark/run.sh`, `README.md`
- [ ] Docker image naming: `<prefix>-go`, `<prefix>-rust`, `<prefix>-zig` — เพิ่มใน table ด้านล่าง
- [ ] `benchmark/run.sh` — Docker-based เสมอ, auto-save ผลใน `benchmark/results/`
- [ ] Statistics output format ตรงกันทั้ง 3 ภาษา (ดู CLAUDE.md)
- [ ] `main()` กระชับ — orchestrate เท่านั้น, logic แยกออกเป็น functions/structs
- [ ] `README.md` มีตารางผลเปรียบเทียบ + key insight

**สำหรับ project ขนาดใหญ่ (มีหลาย epic):** ทำตาม workflow ใน **WORKFLOW.md** ก่อน implement

---

## Docker Image Naming

| Project | Go | Rust | Zig |
|---------|-----|------|-----|
| video-frame-extractor | `vfe-go` | `vfe-rust` | `vfe-zig` |
| hls-stream-segmenter | `hls-go` | `hls-rust` | `hls-zig` |
| subtitle-burn-in-engine | `sbe-go` | `sbe-rust` | `sbe-zig` |
| high-perf-reverse-proxy | `rp-go` | `rp-rust` | `rp-zig` |
| lightweight-api-gateway | `gw-go` | `gw-rust` | `gw-zig` |
| realtime-audio-chunker | `rac-go` | `rac-rust` | `rac-zig` |
| custom-log-masker | `clm-go` | `clm-rust` | `clm-zig` |
| vector-db-ingester | `vdi-go` | `vdi-rust` | `vdi-zig` |
| local-asr-llm-proxy | `asr-go` | `asr-rust` | `asr-zig` |
| log-aggregator-sidecar | `las-go` | `las-rust` | `las-zig` |
| websocket-public-chat | `wsc-go` | `wsc-rust` | `wsc-zig` |

> Project ใหม่: เพิ่ม row ก่อน implement เสมอ

---

## Code Design Rules (เพิ่มเติมจาก CLAUDE.md)

### Go
- `http.Client` ใช้ร่วมกัน (shared) ต่อ worker — ไม่สร้างใหม่ต่อ request
- response body ต้อง drain + close เสมอ: `io.Copy(io.Discard, resp.Body); resp.Body.Close()`
- `parseArgs()` ต้องตรงกับ `CMD` positional args ใน Dockerfile เสมอ

### Rust
- ห้ามรวม HTTP client ไว้ใน `Stats` struct — แยกเป็น `AppState`
- ห้ามใช้ `OnceLock` hack สำหรับ config — ส่งผ่าน state เสมอ
- `reqwest` ต้องใช้ `rustls-tls` เสมอ (ไม่ใช่ native-tls)
- `#[arg(long, action = ArgAction::SetTrue)]` สำหรับ boolean CLI flag

### Zig
- struct ไม่เก็บ allocator — ส่งผ่าน parameter เสมอ
- ทุก heap field ต้อง `allocator.dupe` รวมถึง fallback literals — ห้าม free string literal
- `std.http.Client` ใน request handler → สร้างใหม่ต่อ request หรือเก็บใน global state
