# Task 6.1: Rust Stats — เปลี่ยน Arc<Mutex<Stats>> → AtomicU64

## Status
[TODO]

## Description
ปัจจุบัน Rust ใช้ `Arc<Mutex<Stats>>` สำหรับ counter ธรรมดา (total_messages, dropped_messages, total_connections, active_conns) ทำให้ทุก client ต้องแย่ง Mutex เดียวกันทุกครั้งที่ส่งข้อความ

เปลี่ยนเป็น `AtomicU64` + `Ordering::Relaxed` เพื่อ lock-free counter

**ต้องแก้ทั้ง Profile A และ B** (ไฟล์ stats.rs เหมือนกันทั้งสอง profile)

## Acceptance Criteria
- [ ] `Stats` struct ใช้ `AtomicU64` สำหรับทุก counter field
- [ ] `add_message()`, `add_dropped()`, `add_connection()`, `remove_connection()` เป็น `&self` (ไม่ใช่ `&mut self`)
- [ ] `client.rs` ไม่ต้อง `.lock().await` สำหรับ stats อีกต่อไป — ส่ง `Arc<Stats>` ตรงๆ
- [ ] `main.rs` ไม่ต้อง `Mutex::new(Stats::new())` — ใช้ `Arc::new(Stats::new())` ตรงๆ
- [ ] Unit tests ใน stats.rs ยังคงผ่าน
- [ ] Profile A (Axum) + Profile B (tokio-tungstenite) แก้ทั้งคู่

## Tests Required
- unit test: `test_stats_counters` — verify counter increment/decrement ทำงานถูกต้อง
- unit test: `test_stats_format` — verify print_stats ไม่ panic

## Dependencies
- ไม่มี — standalone refactor

## Files Affected
- `profile-a/rust/src/stats.rs`
- `profile-a/rust/src/client.rs`
- `profile-a/rust/src/main.rs`
- `profile-b/rust/src/stats.rs`
- `profile-b/rust/src/client.rs`
- `profile-b/rust/src/main.rs`

## Implementation Notes

### Before (ปัจจุบัน)
```rust
// stats.rs
pub struct Stats {
    pub total_messages: u64,   // ← ต้อง &mut self
    ...
}

// client.rs
stats.lock().await.add_message();  // ← contention!

// main.rs
let stats = Arc::new(Mutex::new(Stats::new()));
```

### After (เป้าหมาย)
```rust
// stats.rs
use std::sync::atomic::{AtomicU64, Ordering};

pub struct Stats {
    pub total_messages: AtomicU64,
    pub dropped_messages: AtomicU64,
    pub total_connections: AtomicU64,
    pub active_conns: AtomicU64,
    pub start: Instant,
}

impl Stats {
    pub fn add_message(&self) {
        self.total_messages.fetch_add(1, Ordering::Relaxed);
    }
    // ... เปลี่ยนทุก method เป็น &self
}

// client.rs
stats.add_message();  // ← ไม่ต้อง lock!

// main.rs
let stats = Arc::new(Stats::new());
```
