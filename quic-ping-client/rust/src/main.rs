use std::net::UdpSocket;
use std::time::{Duration, Instant};

struct Stats {
    total_processed: u64,
    processing_ns: u128,
}

impl Stats {
    fn avg_latency_ms(&self) -> f64 {
        if self.total_processed == 0 { return 0.0; }
        self.processing_ns as f64 / 1_000_000.0 / self.total_processed as f64
    }
    fn throughput(&self) -> f64 {
        if self.processing_ns == 0 { return 0.0; }
        self.total_processed as f64 * 1_000_000_000.0 / self.processing_ns as f64
    }
}

fn parse_args() -> Result<(String, u16, usize), String> {
    let args: Vec<String> = std::env::args().collect();
    let host = args.get(1).cloned().unwrap_or_else(|| "host.docker.internal".to_string());
    let port = args.get(2).map(|v| v.parse::<u16>()).transpose().map_err(|_| "invalid port".to_string())?.unwrap_or(56000);
    let repeats = args.get(3).map(|v| v.parse::<usize>()).transpose().map_err(|_| "invalid repeats".to_string())?.unwrap_or(3000);
    if repeats == 0 { return Err("invalid repeats".to_string()); }
    Ok((host, port, repeats))
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.total_processed);
    println!("Processing time: {:.3}s", s.processing_ns as f64 / 1_000_000_000.0);
    println!("Average latency: {:.6}ms", s.avg_latency_ms());
    println!("Throughput: {:.2} items/sec", s.throughput());
}

fn main() {
    let (host, port, repeats) = parse_args().unwrap_or_else(|e| { eprintln!("Error: {e}"); std::process::exit(1); });
    let socket = UdpSocket::bind("0.0.0.0:0").unwrap_or_else(|e| { eprintln!("Error: {e}"); std::process::exit(1); });
    socket.connect(format!("{host}:{port}")).unwrap_or_else(|e| { eprintln!("Error: {e}"); std::process::exit(1); });
    socket.set_read_timeout(Some(Duration::from_secs(5))).unwrap_or_else(|e| { eprintln!("Error: {e}"); std::process::exit(1); });

    let start = Instant::now();
    let mut buf = [0u8; 64];
    for _ in 0..repeats {
        socket.send(b"PING").unwrap_or_else(|e| { eprintln!("Error: {e}"); std::process::exit(1); });
        let n = socket.recv(&mut buf).unwrap_or_else(|e| { eprintln!("Error: {e}"); std::process::exit(1); });
        if &buf[..n] != b"PONG" { eprintln!("Error: invalid response"); std::process::exit(1); }
    }

    let s = Stats { total_processed: repeats as u64, processing_ns: start.elapsed().as_nanos() };
    print_stats(&s);
}
