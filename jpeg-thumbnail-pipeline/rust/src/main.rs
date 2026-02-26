use std::fs;
use std::process::Command;
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

fn parse_args() -> Result<(String, String, usize, usize, usize), String> {
    let args: Vec<String> = std::env::args().collect();
    let input = if args.len() > 1 {
        args[1].clone()
    } else {
        "/data/sample.jpg".to_string()
    };
    let output = if args.len() > 2 {
        args[2].clone()
    } else {
        "/tmp/output.jpg".to_string()
    };
    let width = if args.len() > 3 {
        args[3]
            .parse::<usize>()
            .map_err(|_| "width must be positive integer".to_string())?
    } else {
        160
    };
    let height = if args.len() > 4 {
        args[4]
            .parse::<usize>()
            .map_err(|_| "height must be positive integer".to_string())?
    } else {
        90
    };
    let repeats = if args.len() > 5 {
        args[5]
            .parse::<usize>()
            .map_err(|_| "repeats must be positive integer".to_string())?
    } else {
        20
    };

    if width == 0 || height == 0 || repeats == 0 {
        return Err("width, height, repeats must be positive integer".to_string());
    }
    Ok((input, output, width, height, repeats))
}

fn run_ffmpeg(input: &str, output: &str, width: usize, height: usize) -> Result<(), String> {
    let scale = format!("scale={width}:{height}:flags=bilinear");
    let out = Command::new("ffmpeg")
        .args([
            "-loglevel",
            "error",
            "-y",
            "-i",
            input,
            "-vf",
            &scale,
            "-frames:v",
            "1",
            output,
        ])
        .output()
        .map_err(|e| format!("spawn ffmpeg: {e}"))?;

    if !out.status.success() {
        return Err(format!(
            "ffmpeg failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    Ok(())
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
    let (input, output, width, height, repeats) = parse_args().unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    if fs::metadata(&input).is_err() {
        eprintln!("Error: input not found: {input}");
        std::process::exit(1);
    }

    let start = Instant::now();
    for _ in 0..repeats {
        run_ffmpeg(&input, &output, width, height,).unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });
    }

    let stats = Stats {
        total_processed: (width * height * repeats) as u64,
        processing_ns: start.elapsed().as_nanos(),
    };
    print_stats(&stats);
}
