use std::fs;
use std::time::Instant;

#[derive(Clone, Copy)]
struct Target {
    expected_up: bool,
    base_ms: usize,
    jitter_ms: usize,
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
    let input = if args.len() > 1 { args[1].clone() } else { "/data/targets.csv".to_string() };
    let loops = if args.len() > 2 {
        args[2].parse::<usize>().map_err(|_| "loops must be positive integer".to_string())?
    } else {
        5000
    };
    if loops == 0 {
        return Err("loops must be positive integer".to_string());
    }
    Ok((input, loops))
}

fn parse_target(line: &str) -> Result<Target, String> {
    let parts: Vec<&str> = line.split(',').collect();
    if parts.len() != 5 {
        return Err("invalid csv line".to_string());
    }
    let expected_up = parts[2].trim().parse::<bool>().map_err(|_| "invalid expected_up".to_string())?;
    let base_ms = parts[3].trim().parse::<usize>().map_err(|_| "invalid base_ms".to_string())?;
    let jitter_ms = parts[4].trim().parse::<usize>().map_err(|_| "invalid jitter_ms".to_string())?;
    Ok(Target { expected_up, base_ms, jitter_ms })
}

fn load_targets(path: &str) -> Result<Vec<Target>, String> {
    let content = fs::read_to_string(path).map_err(|e| format!("read input: {e}"))?;
    let mut targets = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        targets.push(parse_target(trimmed)?);
    }
    if targets.is_empty() {
        return Err("no targets found".to_string());
    }
    Ok(targets)
}

fn evaluate_status(target: Target, iteration: usize, idx: usize) -> (bool, usize) {
    let seed = (iteration + 1) * 31 + (idx + 1) * 17;
    let latency = target.base_ms + (seed % (target.jitter_ms + 1));
    let flap = seed % 97 == 0;
    let mut up = target.expected_up;
    if flap {
        up = !up;
    }
    (up, latency)
}

fn run_checks(targets: &[Target], loops: usize) -> u64 {
    const FAIL_LIMIT: usize = 3;
    const RECOVER_LIMIT: usize = 2;
    const ALERT_COOLDOWN: usize = 8;

    let mut fail_streak = vec![0usize; targets.len()];
    let mut recover_streak = vec![0usize; targets.len()];
    let mut cooldown = vec![0usize; targets.len()];

    let mut processed: u64 = 0;
    let mut alerts: u64 = 0;

    for i in 0..loops {
        for (idx, target) in targets.iter().enumerate() {
            processed += 1;
            cooldown[idx] = cooldown[idx].saturating_sub(1);

            let (up, latency) = evaluate_status(*target, i, idx);
            if latency > 0 && !up {
                fail_streak[idx] += 1;
                recover_streak[idx] = 0;
            } else {
                recover_streak[idx] += 1;
                fail_streak[idx] = 0;
            }

            if fail_streak[idx] >= FAIL_LIMIT && cooldown[idx] == 0 {
                alerts += 1;
                cooldown[idx] = ALERT_COOLDOWN;
                continue;
            }
            if recover_streak[idx] >= RECOVER_LIMIT && cooldown[idx] == 0 {
                alerts += 1;
            }
        }
    }

    processed + alerts
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.total_processed);
    println!("Processing time: {:.3}s", s.processing_ns as f64 / 1_000_000_000.0);
    println!("Average latency: {:.6}ms", s.avg_latency_ms());
    println!("Throughput: {:.2} checks/sec", s.throughput());
}

fn main() {
    let (input, loops) = parse_args().unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let targets = load_targets(&input).unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let start = Instant::now();
    let total = run_checks(&targets, loops);
    let stats = Stats { total_processed: total, processing_ns: start.elapsed().as_nanos() };
    print_stats(&stats);
}
