use std::time::Instant;

pub struct Stats {
    pub total_messages: u64,
    pub dropped_messages: u64,
    pub total_connections: u64,
    pub active_conns: u64,
    pub start: Instant,
}

impl Stats {
    pub fn new() -> Self {
        Self {
            total_messages: 0,
            dropped_messages: 0,
            total_connections: 0,
            active_conns: 0,
            start: Instant::now(),
        }
    }

    pub fn add_message(&mut self) { self.total_messages += 1; }
    pub fn add_dropped(&mut self) { self.dropped_messages += 1; }
    pub fn add_connection(&mut self) { self.total_connections += 1; self.active_conns += 1; }
    pub fn remove_connection(&mut self) { self.active_conns = self.active_conns.saturating_sub(1); }

    pub fn elapsed_sec(&self) -> f64 {
        self.start.elapsed().as_secs_f64()
    }

    // Returns elapsed_time / message_count (ms per message) — the reciprocal
    // of throughput. Not end-to-end per-message latency; label preserved for
    // shared stats output format compatibility across all projects.
    pub fn avg_latency_ms(&self) -> f64 {
        if self.total_messages == 0 { return 0.0; }
        self.elapsed_sec() * 1000.0 / self.total_messages as f64
    }

    pub fn throughput(&self) -> f64 {
        let elapsed = self.elapsed_sec();
        if elapsed == 0.0 { return 0.0; }
        self.total_messages as f64 / elapsed
    }

    pub fn drop_rate(&self) -> f64 {
        let total = self.total_messages + self.dropped_messages;
        if total == 0 { return 0.0; }
        self.dropped_messages as f64 / total as f64 * 100.0
    }

    pub fn print_stats(&self) {
        println!("--- Statistics ---");
        println!("Total messages: {}", self.total_messages);
        println!("Processing time: {:.3}s", self.elapsed_sec());
        println!("Average latency: {:.3}ms", self.avg_latency_ms());
        println!("Throughput: {:.2} messages/sec", self.throughput());
        println!("Total connections: {}", self.total_connections);
        println!("Message drop rate: {:.2}%", self.drop_rate());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stats_counters() {
        let mut s = Stats::new();
        for _ in 0..100 { s.add_message(); }
        for _ in 0..10  { s.add_dropped(); }
        s.add_connection();
        s.add_connection();
        s.remove_connection();

        assert_eq!(s.total_messages, 100);
        assert_eq!(s.dropped_messages, 10);
        assert_eq!(s.total_connections, 2);
        assert_eq!(s.active_conns, 1);

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
