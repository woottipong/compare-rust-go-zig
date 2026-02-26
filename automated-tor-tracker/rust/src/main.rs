use std::fs::File;
use std::io::{BufRead, BufReader};
use std::time::Instant;

struct Stats {
    total_processed: u64,
    processing_ns: u128,
}

impl Stats {
    fn avg_latency_ms(&self) -> f64 {
        if self.total_processed == 0 {
            return 0.0;
        }
        self.processing_ns as f64 / 1_000_000.0 / self.total_processed as f64
    }

    fn throughput(&self) -> f64 {
        if self.processing_ns == 0 {
            return 0.0;
        }
        self.total_processed as f64 * 1_000_000_000.0 / self.processing_ns as f64
    }
}

fn parse_args() -> Result<(String, usize), String> {
    let args: Vec<String> = std::env::args().collect();
    let input = args.get(1).cloned().unwrap_or_else(|| "/data/tor.txt".to_string());
    let repeats = args
        .get(2)
        .map(|v| v.parse::<usize>())
        .transpose()
        .map_err(|_| "invalid repeats".to_string())?
        .unwrap_or(20000);
    if repeats == 0 {
        return Err("invalid repeats".to_string());
    }
    Ok((input, repeats))
}

fn load_lines(path: &str) -> Result<Vec<String>, String> {
    let file = File::open(path).map_err(|e| format!("open input: {e}"))?;
    let reader = BufReader::new(file);
    let mut lines = Vec::new();
    for line_res in reader.lines() {
        let line = line_res.map_err(|e| format!("read input: {e}"))?;
        let trimmed = line.trim();
        if !trimmed.is_empty() {
            lines.push(trimmed.to_string());
        }
    }
    if lines.is_empty() {
        return Err("empty input".to_string());
    }
    Ok(lines)
}

fn extract_status(line: &str) -> &'static str {
    let lower = line.to_ascii_lowercase();
    if lower.contains("done") || lower.contains("completed") {
        return "done";
    }
    if lower.contains("in progress") || lower.contains("ongoing") {
        return "in_progress";
    }
    if lower.contains("blocked") || lower.contains("risk") {
        return "blocked";
    }
    "todo"
}

fn run_benchmark(lines: &[String], repeats: usize) -> u64 {
    let mut processed = 0u64;
    for _ in 0..repeats {
        for line in lines {
            let _ = extract_status(line);
            processed += 1;
        }
    }
    processed
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.total_processed);
    println!("Processing time: {:.3}s", s.processing_ns as f64 / 1_000_000_000.0);
    println!("Average latency: {:.6}ms", s.avg_latency_ms());
    println!("Throughput: {:.2} items/sec", s.throughput());
}

fn main() {
    let (input, repeats) = parse_args().unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });
    let lines = load_lines(&input).unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });
    let start = Instant::now();
    let processed = run_benchmark(&lines, repeats);
    let s = Stats {
        total_processed: processed,
        processing_ns: start.elapsed().as_nanos(),
    };
    print_stats(&s);
}
