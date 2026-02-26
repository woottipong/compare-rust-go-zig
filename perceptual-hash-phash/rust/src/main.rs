use std::f64::consts::PI;
use std::fs;
use std::process::Command;
use std::time::Instant;

const SIZE: usize = 32;
const LOW_FREQ: usize = 8;

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
    let input = if args.len() > 1 {
        args[1].clone()
    } else {
        "/data/sample.jpg".to_string()
    };
    let repeats = if args.len() > 2 {
        args[2]
            .parse::<usize>()
            .map_err(|_| "repeats must be positive integer".to_string())?
    } else {
        20
    };
    if repeats == 0 {
        return Err("repeats must be positive integer".to_string());
    }
    Ok((input, repeats))
}

fn run_ffmpeg(input: &str, output: &str) -> Result<(), String> {
    let out = Command::new("ffmpeg")
        .args([
            "-loglevel",
            "error",
            "-y",
            "-i",
            input,
            "-vf",
            "scale=32:32,format=gray",
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

fn next_token(data: &[u8], idx: &mut usize) -> Result<String, String> {
    while *idx < data.len() {
        if data[*idx] == b'#' {
            while *idx < data.len() && data[*idx] != b'\n' {
                *idx += 1;
            }
        } else if data[*idx].is_ascii_whitespace() {
            *idx += 1;
        } else {
            break;
        }
    }
    if *idx >= data.len() {
        return Err("unexpected eof".to_string());
    }
    let start = *idx;
    while *idx < data.len() && !data[*idx].is_ascii_whitespace() {
        *idx += 1;
    }
    String::from_utf8(data[start..*idx].to_vec()).map_err(|_| "invalid utf8 token".to_string())
}

fn parse_pgm(data: &[u8]) -> Result<[[f64; SIZE]; SIZE], String> {
    let mut idx = 0usize;
    let magic = next_token(data, &mut idx)?;
    if magic != "P5" {
        return Err("expected P5 pgm".to_string());
    }
    let width = next_token(data, &mut idx)?
        .parse::<usize>()
        .map_err(|_| "invalid width".to_string())?;
    let height = next_token(data, &mut idx)?
        .parse::<usize>()
        .map_err(|_| "invalid height".to_string())?;
    let maxv = next_token(data, &mut idx)?
        .parse::<usize>()
        .map_err(|_| "invalid max value".to_string())?;

    if width != SIZE || height != SIZE || maxv != 255 {
        return Err("invalid pgm header".to_string());
    }

    while idx < data.len() && data[idx].is_ascii_whitespace() {
        idx += 1;
    }

    if data.len() < idx + SIZE * SIZE {
        return Err("pgm payload too short".to_string());
    }

    let mut matrix = [[0.0f64; SIZE]; SIZE];
    for y in 0..SIZE {
        for x in 0..SIZE {
            matrix[y][x] = data[idx + y * SIZE + x] as f64;
        }
    }
    Ok(matrix)
}

fn dct2d(input: [[f64; SIZE]; SIZE]) -> [[f64; SIZE]; SIZE] {
    let mut out = [[0.0f64; SIZE]; SIZE];
    for u in 0..SIZE {
        for v in 0..SIZE {
            let mut sum = 0.0;
            for x in 0..SIZE {
                for y in 0..SIZE {
                    sum += input[y][x]
                        * (((2 * x + 1) as f64 * u as f64 * PI) / 64.0).cos()
                        * (((2 * y + 1) as f64 * v as f64 * PI) / 64.0).cos();
                }
            }
            let cu = if u == 0 { 1.0 / 2.0_f64.sqrt() } else { 1.0 };
            let cv = if v == 0 { 1.0 / 2.0_f64.sqrt() } else { 1.0 };
            out[v][u] = 0.25 * cu * cv * sum;
        }
    }
    out
}

fn phash(matrix: [[f64; SIZE]; SIZE]) -> u64 {
    let dct = dct2d(matrix);
    let mut vals = Vec::with_capacity(LOW_FREQ * LOW_FREQ);
    for y in 0..LOW_FREQ {
        for x in 0..LOW_FREQ {
            vals.push(dct[y][x]);
        }
    }
    let avg = vals.iter().sum::<f64>() / vals.len() as f64;
    let mut hash = 0u64;
    for (i, v) in vals.iter().enumerate() {
        if *v > avg {
            hash |= 1u64 << i;
        }
    }
    hash
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
    if fs::metadata(&input).is_err() {
        eprintln!("Error: input not found: {input}");
        std::process::exit(1);
    }

    let tmp = "/tmp/phash.pgm";
    let start = Instant::now();
    let mut hash = 0u64;

    for _ in 0..repeats {
        run_ffmpeg(&input, tmp).unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });
        let data = fs::read(tmp).unwrap_or_else(|e| {
            eprintln!("Error: read {tmp}: {e}");
            std::process::exit(1);
        });
        let matrix = parse_pgm(&data).unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });
        hash = phash(matrix);
    }

    let _ = fs::remove_file(tmp);
    println!("pHash: {hash:016x}");

    let stats = Stats {
        total_processed: repeats as u64,
        processing_ns: start.elapsed().as_nanos(),
    };
    print_stats(&stats);
}
