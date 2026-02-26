use std::net::{SocketAddr, TcpStream};
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

fn parse_args() -> Result<(String, u16, u16, usize), String> {
    let args: Vec<String> = std::env::args().collect();
    let host = args.get(1).cloned().unwrap_or_else(|| "host.docker.internal".to_string());
    let sp = args.get(2).map(|v| v.parse::<u16>()).transpose().map_err(|_| "invalid start port".to_string())?.unwrap_or(54000);
    let ep = args.get(3).map(|v| v.parse::<u16>()).transpose().map_err(|_| "invalid end port".to_string())?.unwrap_or(54009);
    let repeats = args.get(4).map(|v| v.parse::<usize>()).transpose().map_err(|_| "invalid repeats".to_string())?.unwrap_or(200);
    if ep < sp || repeats == 0 { return Err("invalid args".to_string()); }
    Ok((host, sp, ep, repeats))
}

fn scan(host: &str, sp: u16, ep: u16) -> usize {
    let mut open = 0usize;
    for p in sp..=ep {
        let addr: SocketAddr = format!("{}:{}", host, p).parse().unwrap_or_else(|_| "127.0.0.1:1".parse().unwrap());
        if TcpStream::connect_timeout(&addr, Duration::from_millis(50)).is_ok() {
            open += 1;
        }
    }
    open
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.total_processed);
    println!("Processing time: {:.3}s", s.processing_ns as f64 / 1_000_000_000.0);
    println!("Average latency: {:.6}ms", s.avg_latency_ms());
    println!("Throughput: {:.2} items/sec", s.throughput());
}

fn main() {
    let (host, sp, ep, repeats) = parse_args().unwrap_or_else(|e| { eprintln!("Error: {e}"); std::process::exit(1); });
    let start = Instant::now();
    let mut open = 0usize;
    for _ in 0..repeats { open = scan(&host, sp, ep); }
    println!("Open ports: {}", open);
    let ports_per_run = (ep - sp + 1) as usize;
    let s = Stats { total_processed: (ports_per_run * repeats) as u64, processing_ns: start.elapsed().as_nanos() };
    print_stats(&s);
}
