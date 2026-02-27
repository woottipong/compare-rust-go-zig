use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

pub struct Stats {
    pub total_messages: AtomicU64,
    pub dropped_messages: AtomicU64,
    pub total_connections: AtomicU64,
    pub active_conns: AtomicU64,
    pub start: Instant,
}

impl Stats {
    pub fn new() -> Self {
        Self {
            total_messages: AtomicU64::new(0),
            dropped_messages: AtomicU64::new(0),
            total_connections: AtomicU64::new(0),
            active_conns: AtomicU64::new(0),
            start: Instant::now(),
        }
    }

    pub fn add_message(&self) { self.total_messages.fetch_add(1, Ordering::Relaxed); }
    pub fn add_dropped(&self) { self.dropped_messages.fetch_add(1, Ordering::Relaxed); }
    pub fn add_connection(&self) {
        self.total_connections.fetch_add(1, Ordering::Relaxed);
        self.active_conns.fetch_add(1, Ordering::Relaxed);
    }
    pub fn remove_connection(&self) {
        // Saturating subtract via compare-exchange loop
        loop {
            let current = self.active_conns.load(Ordering::Relaxed);
            let new = current.saturating_sub(1);
            if self.active_conns.compare_exchange_weak(
                current, new, Ordering::Relaxed, Ordering::Relaxed,
            ).is_ok() {
                break;
            }
        }
    }

    pub fn elapsed_sec(&self) -> f64 {
        self.start.elapsed().as_secs_f64()
    }

    // Returns elapsed_time / message_count (ms per message) — the reciprocal
    // of throughput. Not end-to-end per-message latency; label preserved for
    // shared stats output format compatibility across all projects.
    pub fn avg_latency_ms(&self) -> f64 {
        let total = self.total_messages.load(Ordering::Relaxed);
        if total == 0 { return 0.0; }
        self.elapsed_sec() * 1000.0 / total as f64
    }

    pub fn throughput(&self) -> f64 {
        let elapsed = self.elapsed_sec();
        if elapsed == 0.0 { return 0.0; }
        self.total_messages.load(Ordering::Relaxed) as f64 / elapsed
    }

    pub fn drop_rate(&self) -> f64 {
        let msgs = self.total_messages.load(Ordering::Relaxed);
        let dropped = self.dropped_messages.load(Ordering::Relaxed);
        let total = msgs + dropped;
        if total == 0 { return 0.0; }
        dropped as f64 / total as f64 * 100.0
    }

    pub fn print_stats(&self) {
        println!("--- Statistics ---");
        println!("Total messages: {}", self.total_messages.load(Ordering::Relaxed));
        println!("Processing time: {:.3}s", self.elapsed_sec());
        println!("Average latency: {:.3}ms", self.avg_latency_ms());
        println!("Throughput: {:.2} messages/sec", self.throughput());
        println!("Total connections: {}", self.total_connections.load(Ordering::Relaxed));
        println!("Message drop rate: {:.2}%", self.drop_rate());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stats_counters() {
        let s = Stats::new();
        for _ in 0..100 { s.add_message(); }
        for _ in 0..10  { s.add_dropped(); }
        s.add_connection();
        s.add_connection();
        s.remove_connection();

        assert_eq!(s.total_messages.load(Ordering::Relaxed), 100);
        assert_eq!(s.dropped_messages.load(Ordering::Relaxed), 10);
        assert_eq!(s.total_connections.load(Ordering::Relaxed), 2);
        assert_eq!(s.active_conns.load(Ordering::Relaxed), 1);

        let dr = s.drop_rate();
        assert!(dr > 9.0 && dr < 10.0, "drop rate {dr:.2} not in 9-10%");
        assert!(s.throughput() > 0.0);
    }

    #[test]
    fn test_stats_format() {
        let s = Stats::new();
        // verify print_stats doesn't panic (output goes to stdout)
        s.print_stats();
    }
}
