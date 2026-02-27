# Task 9.1: รัน Benchmark ใหม่หลังแก้ code

## Status
[TODO]

## Description
หลังจาก Epic 6 (Rust fix), Epic 7 (Go fix), และ Epic 8 (Benchmark improve) เสร็จ:
1. รัน benchmark Profile A ใหม่
2. รัน benchmark Profile B ใหม่
3. เปรียบเทียบกับผลเก่า (baseline: 2026-02-28 00:14:55 / 00:39:51)

## Acceptance Criteria
- [ ] ผล Profile A ใหม่บันทึกไว้ที่ benchmark/results/
- [ ] ผล Profile B ใหม่บันทึกไว้ที่ benchmark/results/
- [ ] Rust saturation throughput เพิ่มขึ้นอย่างมีนัยสำคัญ (>1,500 msg/s target)
- [ ] Go saturation peak memory ลดลง (target <150 MiB)
- [ ] มี CPU metrics ในผลใหม่

## Tests Required
- ไม่มี — เป็น benchmark run

## Dependencies
- Task 6.3 (Rust verified)
- Task 7.2 (Go verified)
- Task 8.2 (Multi-run + stdev)

## Files Affected
- `benchmark/results/` — ไฟล์ผลใหม่
