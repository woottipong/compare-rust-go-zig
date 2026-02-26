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
    let input = if args.len() > 1 {
        args[1].clone()
    } else {
        "/data/sample.parquet".to_string()
    };
    let repeats = if args.len() > 2 {
        args[2]
            .parse::<usize>()
            .map_err(|_| "repeats must be positive integer".to_string())?
    } else {
        40
    };
    if repeats == 0 {
        return Err("repeats must be positive integer".to_string());
    }
    Ok((input, repeats))
}

fn read_uvarint(data: &[u8], idx: &mut usize) -> Result<u64, String> {
    let mut x: u64 = 0;
    let mut s = 0;
    for _ in 0..10 {
        if *idx >= data.len() {
            return Err("unexpected eof in varint".to_string());
        }
        let b = data[*idx];
        *idx += 1;
        if b < 0x80 {
            return Ok(x | ((b as u64) << s));
        }
        x |= ((b & 0x7f) as u64) << s;
        s += 7;
    }
    Err("varint overflow".to_string())
}

fn unpack_bitpacked(src: &[u8], bit_width: usize, count: usize, out: &mut Vec<u32>) {
    let mut bit_pos = 0usize;
    for _ in 0..count {
        let mut v = 0u32;
        for b in 0..bit_width {
            let byte_idx = (bit_pos + b) / 8;
            let bit_idx = (bit_pos + b) % 8;
            if byte_idx < src.len() && ((src[byte_idx] >> bit_idx) & 1) == 1 {
                v |= 1u32 << b;
            }
        }
        out.push(v);
        bit_pos += bit_width;
    }
}

fn decode_hybrid(encoded: &[u8], bit_width: usize, expected: usize) -> Result<Vec<u32>, String> {
    let mut values: Vec<u32> = Vec::with_capacity(expected);
    let mut idx = 0usize;

    while idx < encoded.len() && values.len() < expected {
        let header = read_uvarint(encoded, &mut idx)?;
        if (header & 1) == 0 {
            let run = (header >> 1) as usize;
            let byte_width = (bit_width + 7) / 8;
            if idx + byte_width > encoded.len() {
                return Err("invalid rle payload".to_string());
            }
            let mut value = 0u32;
            for i in 0..byte_width {
                value |= (encoded[idx + i] as u32) << (8 * i);
            }
            idx += byte_width;
            for _ in 0..run {
                if values.len() == expected {
                    break;
                }
                values.push(value);
            }
        } else {
            let groups = (header >> 1) as usize;
            let n = groups * 8;
            let byte_count = groups * bit_width;
            if idx + byte_count > encoded.len() {
                return Err("invalid bitpack payload".to_string());
            }
            unpack_bitpacked(&encoded[idx..idx + byte_count], bit_width, n, &mut values);
            idx += byte_count;
        }
    }

    if values.len() > expected {
        values.truncate(expected);
    }
    if values.len() != expected {
        return Err("decoded size mismatch".to_string());
    }
    Ok(values)
}

fn process_file(path: &str) -> Result<usize, String> {
    let data = fs::read(path).map_err(|e| format!("read input: {e}"))?;
    if data.len() < 17 {
        return Err("file too small".to_string());
    }
    if &data[0..4] != b"PAR1" || &data[data.len() - 4..] != b"PAR1" {
        return Err("invalid parquet magic".to_string());
    }

    let meta_len = u32::from_le_bytes([
        data[data.len() - 8],
        data[data.len() - 7],
        data[data.len() - 6],
        data[data.len() - 5],
    ]) as usize;

    if data.len() < 8 + meta_len + 13 {
        return Err("invalid metadata length".to_string());
    }

    let bit_width = data[4] as usize;
    let num_values = u32::from_le_bytes([data[5], data[6], data[7], data[8]]) as usize;
    let encoded_len = u32::from_le_bytes([data[9], data[10], data[11], data[12]]) as usize;

    if 13 + encoded_len > data.len() - 8 - meta_len {
        return Err("invalid encoded section".to_string());
    }

    let _decoded = decode_hybrid(&data[13..13 + encoded_len], bit_width, num_values)?;
    Ok(num_values)
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
    let mut n = 0usize;
    for _ in 0..repeats {
        n = process_file(&input).unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });
    }

    let stats = Stats {
        total_processed: (n * repeats) as u64,
        processing_ns: start.elapsed().as_nanos(),
    };
    print_stats(&stats);
}
