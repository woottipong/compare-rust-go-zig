# Task 7.1: Go — ลด sendBufSize + Read/WriteBufferSize

## Status
[TODO]

## Description
Go ใช้ memory สูงใน saturation (195–207 MiB) สาเหตุหลักมาจาก:
1. `sendBufSize = 256` — buffered channel ใหญ่เกินจำเป็น ที่ 1,000 clients = 256 KB × 1,000 = 250 MB ทาง potential
2. `ReadBufferSize/WriteBufferSize = 1024` — สำหรับ 128-byte message ใหญ่เกินไป

ลดค่าเหล่านี้เพื่อลด memory footprint โดย throughput ไม่ลดลงเพราะ message ที่ช้ากว่า buffer จะถูก drop อยู่แล้ว

**ต้องแก้ทั้ง Profile A และ B**

## Acceptance Criteria
- [ ] `sendBufSize` ลดจาก 256 → 64
- [ ] `ReadBufferSize` ลดจาก 1024 → 512
- [ ] `WriteBufferSize` ลดจาก 1024 → 512
- [ ] Unit tests ทั้งหมดผ่าน
- [ ] Profile A (GoFiber) + Profile B (net/http) แก้ทั้งคู่

## Tests Required
- `go test ./...` ใน profile-a/go/ — ผ่าน
- `go test ./...` ใน profile-b/go/ — ผ่าน

## Dependencies
- ไม่มี — standalone change

## Files Affected
- `profile-a/go/client.go`
- `profile-b/go/client.go`

## Implementation Notes

### Changes
```diff
 const (
     writeWait      = 10 * time.Second
     pongWait       = 60 * time.Second
     pingPeriod     = PingIntervalSec * time.Second
     maxMessageSize = 512
-    sendBufSize    = 256
+    sendBufSize    = 64
     tokenBucketMax = RateLimitMsgPerSec
 )

 var upgrader = websocket.Upgrader{
-    ReadBufferSize:  1024,
-    WriteBufferSize: 1024,
+    ReadBufferSize:  512,
+    WriteBufferSize: 512,
     CheckOrigin:     func(r *http.Request) bool { return true },
 }
```

### ทำไม 64 ไม่ใช่ 32?
- ที่ 5 msg/s × 1,000 clients = 5,000 inbound msg/s
- broadcast ต้องส่ง ~999 msg per inbound → write rate สูง
- buffer 64 ให้ headroom ~12 sec ของ messages ก่อน drop
- ถ้า consumer ช้ากว่า 12 sec ก็ควร drop แทนที่จะ buffer ต่อ
