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
| json-transform-pipeline | `jtp-go` | `jtp-rust` | `jtp-zig` |
| zstd-compression | `zst-go` | `zst-rust` | `zst-zig` |

> Project ใหม่: เพิ่ม row ก่อน implement เสมอ

