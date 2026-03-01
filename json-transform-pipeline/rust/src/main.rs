use serde::Deserialize;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::time::Instant;

#[derive(Deserialize)]
struct Record {
    #[allow(dead_code)]
    id: u64,
    #[allow(dead_code)]
    name: String,
    score: f64,
    #[allow(dead_code)]
    active: bool,
}

struct Stats {
    total_processed: u64,
    processing_ns: u128,
    score_sum: f64,
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

fn process_file(path: &str) -> Result<Stats, Box<dyn std::error::Error>> {
    let file = File::open(path)?;
    let reader = BufReader::new(file);

    let mut total_processed: u64 = 0;
    let mut score_sum: f64 = 0.0;

    let start = Instant::now();

    for line in reader.lines() {
        let line = line?;
        if line.is_empty() {
            continue;
        }
        if let Ok(rec) = serde_json::from_str::<Record>(&line) {
            score_sum += rec.score;
            total_processed += 1;
        }
    }

    let processing_ns = start.elapsed().as_nanos();

    Ok(Stats {
        total_processed,
        processing_ns,
        score_sum,
    })
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.total_processed);
    println!("Processing time: {:.3}s", s.processing_ns as f64 / 1_000_000_000.0);
    println!("Average latency: {:.6}ms", s.avg_latency_ms());
    println!("Throughput: {:.2} items/sec", s.throughput());
    println!("Score sum: {:.2}", s.score_sum);
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let input_path = args.get(1).map(|s| s.as_str()).unwrap_or("/data/records.jsonl");
    let repeats: usize = args
        .get(2)
        .and_then(|s| s.parse().ok())
        .unwrap_or(1);

    let mut best: Option<Stats> = None;

    for _ in 0..repeats {
        match process_file(input_path) {
            Ok(s) => {
                let is_better = best.as_ref().map_or(true, |b| s.processing_ns < b.processing_ns);
                if is_better {
                    best = Some(s);
                }
            }
            Err(e) => {
                eprintln!("error: {}", e);
                std::process::exit(1);
            }
        }
    }

    if let Some(s) = best {
        print_stats(&s);
    }
}
