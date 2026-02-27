# Task 6.3: Rust — รัน unit tests ทั้งหมด verify refactor

## Status
[TODO]

## Description
หลังจากแก้ Task 6.1 (AtomicU64 Stats) และ 6.2 (broadcast try_send) ต้อง verify ว่า:
1. `cargo test` ผ่านทั้ง Profile A และ B
2. `docker build` ผ่านทั้งคู่
3. ไม่มี compile warning ที่เกี่ยวข้อง

## Acceptance Criteria
- [ ] `cd profile-a/rust && cargo test` — ผ่านทั้งหมด
- [ ] `cd profile-b/rust && cargo test` — ผ่านทั้งหมด
- [ ] `docker build -t wsca-rust profile-a/rust/` — สำเร็จ
- [ ] `docker build -t wsc-rust profile-b/rust/` — สำเร็จ
- [ ] ไม่มี compile warning เกี่ยวกับ unused import (Mutex ที่ไม่ใช้แล้ว)

## Tests Required
- `stats::tests::test_stats_counters` — verify AtomicU64 counters
- `stats::tests::test_stats_format` — verify print_stats
- `hub::tests::test_broadcast_to_others` — verify broadcast ยัง fan-out ถูกต้อง
- `hub::tests::test_state_cleanup` — verify remove state
- `client::tests::test_rate_limit_drop` — verify rate limiter
- `client::tests::test_rate_limit_refill` — verify token refill

## Dependencies
- Task 6.1 (AtomicU64 Stats)
- Task 6.2 (Broadcast fix)

## Files Affected
- ไม่แก้ไฟล์ — เป็น verification task เท่านั้น
