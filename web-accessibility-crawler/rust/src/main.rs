use std::fs;
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
    let input = args.get(1).cloned().unwrap_or_else(|| "/data/pages.html".to_string());
    let repeats = args
        .get(2)
        .map(|v| v.parse::<usize>())
        .transpose()
        .map_err(|_| "invalid repeats".to_string())?
        .unwrap_or(100000);
    if repeats == 0 {
        return Err("invalid repeats".to_string());
    }
    Ok((input, repeats))
}

fn load_pages(path: &str) -> Result<Vec<String>, String> {
    let content = fs::read_to_string(path).map_err(|e| format!("read input: {e}"))?;
    let pages: Vec<String> = content
        .split("\n===\n")
        .map(|p| p.trim().to_string())
        .filter(|p| !p.is_empty())
        .collect();
    if pages.is_empty() {
        return Err("no pages found".to_string());
    }
    Ok(pages)
}

fn count_issues(page: &str) -> u64 {
    let lower = page.to_ascii_lowercase();
    let mut issues = 0u64;
    if !lower.contains("<html") || !lower.contains("lang=") {
        issues += 1;
    }
    if !lower.contains("<title") {
        issues += 1;
    }
    let img_count = lower.matches("<img").count() as u64;
    let alt_count = lower.matches("alt=").count() as u64;
    if alt_count < img_count {
        issues += img_count - alt_count;
    }
    if lower.contains("<a ") && !lower.contains("aria-label=") {
        issues += 1;
    }
    issues
}

fn run_benchmark(pages: &[String], repeats: usize) -> u64 {
    let mut processed = 0u64;
    for _ in 0..repeats {
        for p in pages {
            let _ = count_issues(p);
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
    let pages = load_pages(&input).unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });
    let start = Instant::now();
    let processed = run_benchmark(&pages, repeats);
    let s = Stats {
        total_processed: processed,
        processing_ns: start.elapsed().as_nanos(),
    };
    print_stats(&s);
}
