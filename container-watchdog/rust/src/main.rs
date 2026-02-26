use std::fs;
use std::time::Instant;

#[derive(Clone, Copy)]
struct Sample {
    cpu: f64,
    mem: f64,
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

fn parse_args() -> Result<(String, usize), String> {
    let args: Vec<String> = std::env::args().collect();
    let input = if args.len() > 1 { args[1].clone() } else { "/data/metrics.csv".to_string() };
    let loops = if args.len() > 2 {
        args[2].parse::<usize>().map_err(|_| "loops must be positive integer".to_string())?
    } else {
        200
    };
    if loops == 0 {
        return Err("loops must be positive integer".to_string());
    }
    Ok((input, loops))
}

fn parse_line(line: &str) -> Result<Sample, String> {
    let parts: Vec<&str> = line.split(',').collect();
    if parts.len() != 3 {
        return Err("invalid csv line".to_string());
    }
    let cpu = parts[1].parse::<f64>().map_err(|_| "invalid cpu".to_string())?;
    let mem = parts[2].parse::<f64>().map_err(|_| "invalid mem".to_string())?;
    Ok(Sample { cpu, mem })
}

fn load_samples(path: &str) -> Result<Vec<Sample>, String> {
    let content = fs::read_to_string(path).map_err(|e| format!("read input: {e}"))?;
    let mut samples = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        samples.push(parse_line(trimmed)?);
    }
    if samples.is_empty() {
        return Err("no samples found".to_string());
    }
    Ok(samples)
}

fn process(samples: &[Sample], loops: usize) -> u64 {
    const CPU_THRESHOLD: f64 = 85.0;
    const MEM_THRESHOLD: f64 = 90.0;
    const STREAK_LIMIT: usize = 3;
    const COOLDOWN_TICKS: usize = 20;

    let mut cpu_streak = 0usize;
    let mut mem_streak = 0usize;
    let mut cooldown = 0usize;
    let mut actions = 0u64;
    let mut processed = 0u64;

    for _ in 0..loops {
        for sample in samples {
            processed += 1;
            cooldown = cooldown.saturating_sub(1);

            if sample.cpu > CPU_THRESHOLD { cpu_streak += 1; } else { cpu_streak = 0; }
            if sample.mem > MEM_THRESHOLD { mem_streak += 1; } else { mem_streak = 0; }

            if mem_streak >= STREAK_LIMIT && cooldown == 0 {
                actions += 1;
                cooldown = COOLDOWN_TICKS;
                mem_streak = 0;
                cpu_streak = 0;
                continue;
            }
            if cpu_streak >= STREAK_LIMIT {
                actions += 1;
                cpu_streak = 0;
            }
        }
    }

    processed + actions
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.total_processed);
    println!("Processing time: {:.3}s", s.processing_ns as f64 / 1_000_000_000.0);
    println!("Average latency: {:.6}ms", s.avg_latency_ms());
    println!("Throughput: {:.2} items/sec", s.throughput());
}

fn main() {
    let (input, loops) = parse_args().unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let samples = load_samples(&input).unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let start = Instant::now();
    let total = process(&samples, loops);
    let s = Stats { total_processed: total, processing_ns: start.elapsed().as_nanos() };
    print_stats(&s);
}
