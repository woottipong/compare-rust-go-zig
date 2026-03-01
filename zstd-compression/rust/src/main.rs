use std::fs;
use std::io::{Read, Write};
use std::time::Instant;

struct Stats {
    input_bytes: u64,
    compress_ns: u128,
    decompress_ns: u128,
    compressed_bytes: u64,
}

impl Stats {
    fn compress_throughput_mbs(&self) -> f64 {
        if self.compress_ns == 0 {
            return 0.0;
        }
        self.input_bytes as f64 / 1e6 / (self.compress_ns as f64 / 1e9)
    }

    fn decompress_throughput_mbs(&self) -> f64 {
        if self.decompress_ns == 0 {
            return 0.0;
        }
        self.input_bytes as f64 / 1e6 / (self.decompress_ns as f64 / 1e9)
    }

    fn compression_ratio(&self) -> f64 {
        if self.compressed_bytes == 0 {
            return 0.0;
        }
        self.input_bytes as f64 / self.compressed_bytes as f64
    }
}

fn process_file(path: &str) -> Result<Stats, Box<dyn std::error::Error>> {
    let data = fs::read(path)?;
    let input_bytes = data.len() as u64;

    // Compress
    let compress_start = Instant::now();
    let mut encoder = zstd::Encoder::new(Vec::new(), 3)?;
    encoder.write_all(&data)?;
    let compressed = encoder.finish()?;
    let compress_ns = compress_start.elapsed().as_nanos();
    let compressed_bytes = compressed.len() as u64;

    // Decompress
    let decompress_start = Instant::now();
    let mut decoder = zstd::Decoder::new(compressed.as_slice())?;
    let mut decompressed = Vec::with_capacity(data.len());
    decoder.read_to_end(&mut decompressed)?;
    let decompress_ns = decompress_start.elapsed().as_nanos();

    // Verify round-trip
    if decompressed.len() != data.len() {
        return Err(format!(
            "round-trip size mismatch: {} != {}",
            decompressed.len(),
            data.len()
        )
        .into());
    }

    Ok(Stats {
        input_bytes,
        compress_ns,
        decompress_ns,
        compressed_bytes,
    })
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.input_bytes);
    println!(
        "Processing time: {:.3}s",
        (s.compress_ns + s.decompress_ns) as f64 / 1_000_000_000.0
    );
    println!(
        "Average latency: {:.6}ms",
        (s.compress_ns + s.decompress_ns) as f64 / 1_000_000.0
    );
    println!("Throughput: {:.2} items/sec", s.compress_throughput_mbs());
    println!("Input size: {:.2} MB", s.input_bytes as f64 / 1e6);
    println!("Compressed size: {:.2} MB", s.compressed_bytes as f64 / 1e6);
    println!("Compression ratio: {:.2}x", s.compression_ratio());
    println!("Compress speed: {:.2} MB/s", s.compress_throughput_mbs());
    println!("Decompress speed: {:.2} MB/s", s.decompress_throughput_mbs());
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let input_path = args.get(1).map(|s| s.as_str()).unwrap_or("/data/logs.txt");
    let repeats: usize = args
        .get(2)
        .and_then(|s| s.parse().ok())
        .unwrap_or(1);

    let mut best: Option<Stats> = None;

    for _ in 0..repeats {
        match process_file(input_path) {
            Ok(s) => {
                let is_better = best
                    .as_ref()
                    .map_or(true, |b| (s.compress_ns + s.decompress_ns) < (b.compress_ns + b.decompress_ns));
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
