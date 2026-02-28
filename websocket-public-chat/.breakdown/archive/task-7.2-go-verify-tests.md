# Task 7.2: Go — รัน unit tests ทั้งหมด verify

## Status
[DONE]

## Description
หลังจากแก้ Task 7.1 (ลด buffer sizes) ต้อง verify ว่า:
1. `go test ./...` ผ่านทั้ง Profile A และ B
2. `docker build` ผ่านทั้งคู่

## Acceptance Criteria
- [x] `cd profile-a/go && go test ./...` — ผ่านทั้งหมด
- [x] `cd profile-b/go && go test ./...` — ผ่านทั้งหมด
- [x] `docker build -t wsca-go profile-a/go/` — สำเร็จ
- [x] `docker build -t wsc-go profile-b/go/` — สำเร็จ

## Tests Required
- `TestRateLimiter` — verify token bucket
- `TestBroadcastExcept` — verify broadcast fan-out
- `TestStatsCounters` — verify stats counters
- `TestHubRegisterUnregister` — verify hub lifecycle

## Dependencies
- Task 7.1 (ลด buffer sizes)

## Files Affected
- ไม่แก้ไฟล์ — เป็น verification task เท่านั้น
