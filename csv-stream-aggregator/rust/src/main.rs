use std::collections::HashMap;
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

#[derive(Clone, Copy, Default)]
struct Aggregate {
    count: u64,
    sum: f64,
}

fn parse_args() -> Result<(String, usize), String> {
    let args: Vec<String> = std::env::args().collect();
    let input = if args.len() > 1 {
        args[1].clone()
    } else {
        "/data/sales.csv".to_string()
    };
    let repeats = if args.len() > 2 {
        args[2]
            .parse::<usize>()
            .map_err(|_| "repeats must be positive integer".to_string())?
    } else {
        30
    };
    if repeats == 0 {
        return Err("repeats must be positive integer".to_string());
    }
    Ok((input, repeats))
}

fn process_file(path: &str) -> Result<(u64, HashMap<String, Aggregate>), String> {
    let file = File::open(path).map_err(|e| format!("open input: {e}"))?;
    let reader = BufReader::new(file);

    let mut map: HashMap<String, Aggregate> = HashMap::new();
    let mut rows: u64 = 0;

    for (line_no, line) in reader.lines().enumerate() {
        let line = line.map_err(|e| format!("read line: {e}"))?;
        if line_no == 0 && line.starts_with("category,") {
            continue;
        }
        let mut parts = line.split(',');
        let category = match parts.next() {
            Some(v) if !v.is_empty() => v,
            _ => continue,
        };
        let amount = match parts.next().and_then(|v| v.parse::<f64>().ok()) {
            Some(v) => v,
            None => continue,
        };

        let entry = map.entry(category.to_string()).or_default();
        entry.count += 1;
        entry.sum += amount;
        rows += 1;
    }

    Ok((rows, map))
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.total_processed);
    println!(
        "Processing time: {:.3}s",
        s.processing_ns as f64 / 1_000_000_000.0
    );
    println!("Average latency: {:.6}ms", s.avg_latency_ms());
    println!("Throughput: {:.2} items/sec", s.throughput());
}

fn main() {
    let (input, repeats) = parse_args().unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let start = Instant::now();
    let mut rows: u64 = 0;
    let mut aggs: HashMap<String, Aggregate> = HashMap::new();

    for _ in 0..repeats {
        let (r, a) = process_file(&input).unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });
        rows = r;
        aggs = a;
    }
    let _ = aggs;

    let stats = Stats {
        total_processed: rows * repeats as u64,
        processing_ns: start.elapsed().as_nanos(),
    };
    print_stats(&stats);
}
