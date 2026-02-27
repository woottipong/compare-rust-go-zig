# Task 7.2: Go — รัน unit tests ทั้งหมด verify

## Status
[TODO]

## Description
หลังจากแก้ Task 7.1 (ลด buffer sizes) ต้อง verify ว่า:
1. `go test ./...` ผ่านทั้ง Profile A และ B
2. `docker build` ผ่านทั้งคู่

## Acceptance Criteria
- [ ] `cd profile-a/go && go test ./...` — ผ่านทั้งหมด
- [ ] `cd profile-b/go && go test ./...` — ผ่านทั้งหมด
- [ ] `docker build -t wsca-go profile-a/go/` — สำเร็จ
- [ ] `docker build -t wsc-go profile-b/go/` — สำเร็จ

## Tests Required
- `TestRateLimiter` — verify token bucket
- `TestBroadcastExcept` — verify broadcast fan-out
- `TestStatsCounters` — verify stats counters
- `TestHubRegisterUnregister` — verify hub lifecycle

## Dependencies
- Task 7.1 (ลด buffer sizes)

## Files Affected
- ไม่แก้ไฟล์ — เป็น verification task เท่านั้น
