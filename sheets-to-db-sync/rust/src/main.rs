use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::time::Instant;

#[derive(Clone)]
struct Record {
    id: String,
    name: String,
    email: String,
    updated_at: String,
}

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

fn parse_args() -> Result<(String, String, usize), String> {
    let args: Vec<String> = std::env::args().collect();
    let sheet_path = args.get(1).cloned().unwrap_or_else(|| "/data/sheet.csv".to_string());
    let db_path = args.get(2).cloned().unwrap_or_else(|| "/data/db.csv".to_string());
    let repeats = args
        .get(3)
        .map(|v| v.parse::<usize>())
        .transpose()
        .map_err(|_| "invalid repeats".to_string())?
        .unwrap_or(1000);
    if repeats == 0 {
        return Err("invalid repeats".to_string());
    }
    Ok((sheet_path, db_path, repeats))
}

fn parse_csv(path: &str) -> Result<Vec<Record>, String> {
    let file = File::open(path).map_err(|e| format!("open csv: {e}"))?;
    let reader = BufReader::new(file);
    let mut rows = Vec::new();

    for (idx, line_res) in reader.lines().enumerate() {
        let line = line_res.map_err(|e| format!("read csv: {e}"))?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if idx == 0 && trimmed.starts_with("id,") {
            continue;
        }
        let parts: Vec<&str> = trimmed.split(',').collect();
        if parts.len() != 4 {
            return Err(format!("invalid csv row at line {}", idx + 1));
        }
        rows.push(Record {
            id: parts[0].to_string(),
            name: parts[1].to_string(),
            email: parts[2].to_string(),
            updated_at: parts[3].to_string(),
        });
    }

    Ok(rows)
}

fn to_map(rows: &[Record]) -> HashMap<String, Record> {
    let mut map = HashMap::with_capacity(rows.len());
    for r in rows {
        map.insert(r.id.clone(), r.clone());
    }
    map
}

fn sync_rows(sheet_rows: &[Record], db_map: &mut HashMap<String, Record>) {
    for r in sheet_rows {
        db_map.insert(r.id.clone(), r.clone());
    }
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.total_processed);
    println!("Processing time: {:.3}s", s.processing_ns as f64 / 1_000_000_000.0);
    println!("Average latency: {:.6}ms", s.avg_latency_ms());
    println!("Throughput: {:.2} items/sec", s.throughput());
}

fn main() {
    let (sheet_path, db_path, repeats) = parse_args().unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let sheet_rows = parse_csv(&sheet_path).unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let db_rows = parse_csv(&db_path).unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let mut db_map = to_map(&db_rows);
    let start = Instant::now();

    for _ in 0..repeats {
        sync_rows(&sheet_rows, &mut db_map);
    }

    let s = Stats {
        total_processed: (sheet_rows.len() * repeats) as u64,
        processing_ns: start.elapsed().as_nanos(),
    };
    print_stats(&s);
}
