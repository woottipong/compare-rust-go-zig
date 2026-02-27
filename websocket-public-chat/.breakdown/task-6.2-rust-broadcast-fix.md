# Task 6.2: Rust Broadcast — แก้ blocking await ใน RwLock → try_send

## Status
[TODO]

## Description
`broadcast_except()` ปัจจุบัน hold `RwLock` read guard ตลอดรอบ broadcast และใช้ `tx.send(msg.clone()).await` ซึ่ง **await ภายใน lock** — ถ้า receiver ช้า จะ block ทั้ง broadcast loop ทำให้ throughput ต่ำ 560 msg/s (เทียบกับ Go 2,551 และ Zig 2,951)

แก้โดย:
1. Copy sender list ขณะ hold lock → release lock → fan-out with `try_send`
2. `try_send` เป็น non-blocking — ถ้า channel full ก็ skip (เหมือน Go ที่ใช้ `select { default: }`)

**ต้องแก้ทั้ง Profile A และ B**

## Acceptance Criteria
- [ ] `broadcast_except()` ไม่ hold lock ระหว่าง send
- [ ] ใช้ `try_send()` แทน `send().await` — non-blocking
- [ ] ไม่มี `.await` ภายใน `RwLock` guard scope
- [ ] Unit tests: `test_broadcast_to_others` ยังคงผ่าน
- [ ] Unit tests: `test_state_cleanup` ยังคงผ่าน
- [ ] Profile A (Axum) + Profile B (tokio-tungstenite) แก้ทั้งคู่

## Tests Required
- unit test: `test_broadcast_to_others` — verify ว่า sender ไม่ได้รับ, ที่เหลือได้รับ
- unit test: `test_state_cleanup` — verify remove แล้ว map ว่าง
- unit test (ใหม่): `test_broadcast_full_channel` — verify ว่า channel full ไม่ panic

## Dependencies
- ไม่มี — standalone refactor (ทำพร้อม 6.1 ได้)

## Files Affected
- `profile-a/rust/src/hub.rs`
- `profile-b/rust/src/hub.rs`

## Implementation Notes

### Before (ปัจจุบัน) — ⚠️ await inside lock
```rust
pub async fn broadcast_except(clients: &Clients, sender_id: Uuid, msg: WsMessage) {
    let guard = clients.read().await;         // ← lock acquired
    for (id, tx) in guard.iter() {
        if *id == sender_id { continue; }
        let _ = tx.send(msg.clone()).await;   // ← AWAIT inside lock!
    }
    // ← lock released here — could be seconds later
}
```

### After (เป้าหมาย) — lock-free fan-out
```rust
pub async fn broadcast_except(clients: &Clients, sender_id: Uuid, msg: WsMessage) {
    // Step 1: copy sender list under lock
    let targets: Vec<mpsc::Sender<WsMessage>> = {
        let guard = clients.read().await;
        guard.iter()
            .filter(|(id, _)| **id != sender_id)
            .map(|(_, tx)| tx.clone())
            .collect()
    }; // ← lock released immediately

    // Step 2: fan-out without holding lock
    for tx in targets {
        let _ = tx.try_send(msg.clone()); // non-blocking
    }
}
```

### ทำไม try_send ไม่ใช่ send().await?
- `send().await` จะ suspend task ถ้า channel full → block อีก client
- `try_send()` จะ return Err ทันทีถ้า full → skip เหมือนที่ Go ทำ
- Go ใช้ `select { case ch <- msg: default: }` ซึ่งเป็น pattern เดียวกัน
