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

fn parse_args() -> Result<(String, String, usize), String> {
    let args: Vec<String> = std::env::args().collect();
    let input = if args.len() > 1 {
        args[1].clone()
    } else {
        "/data/sample.ppm".to_string()
    };
    let output = if args.len() > 2 {
        args[2].clone()
    } else {
        "/tmp/output.png".to_string()
    };
    let repeats = if args.len() > 3 {
        args[3]
            .parse::<usize>()
            .map_err(|_| "repeats must be positive integer".to_string())?
    } else {
        30
    };
    if repeats == 0 {
        return Err("repeats must be positive integer".to_string());
    }
    Ok((input, output, repeats))
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

fn parse_ppm(data: &[u8]) -> Result<(usize, usize, Vec<u8>), String> {
    let mut idx = 0usize;
    let magic = next_token(data, &mut idx)?;
    if magic != "P6" {
        return Err("only P6 ppm supported".to_string());
    }
    let width = next_token(data, &mut idx)?
        .parse::<usize>()
        .map_err(|_| "invalid width".to_string())?;
    let height = next_token(data, &mut idx)?
        .parse::<usize>()
        .map_err(|_| "invalid height".to_string())?;
    let maxv = next_token(data, &mut idx)?
        .parse::<u32>()
        .map_err(|_| "invalid max value".to_string())?;
    if width == 0 || height == 0 || maxv != 255 {
        return Err("invalid ppm header".to_string());
    }
    while idx < data.len() && data[idx].is_ascii_whitespace() {
        idx += 1;
    }
    let expected = width * height * 3;
    if data.len() < idx + expected {
        return Err("ppm payload too short".to_string());
    }
    Ok((width, height, data[idx..idx + expected].to_vec()))
}

fn adler32(data: &[u8]) -> u32 {
    const MOD: u32 = 65521;
    let mut s1: u32 = 1;
    let mut s2: u32 = 0;
    for b in data {
        s1 = (s1 + *b as u32) % MOD;
        s2 = (s2 + s1) % MOD;
    }
    (s2 << 16) | s1
}

fn crc32_table() -> [u32; 256] {
    let mut table = [0u32; 256];
    let mut i = 0usize;
    while i < 256 {
        let mut c = i as u32;
        for _ in 0..8 {
            if c & 1 == 1 {
                c = 0xedb88320 ^ (c >> 1);
            } else {
                c >>= 1;
            }
        }
        table[i] = c;
        i += 1;
    }
    table
}

fn crc32(data: &[u8]) -> u32 {
    let table = crc32_table();
    let mut c: u32 = 0xffff_ffff;
    for b in data {
        let idx = ((c ^ (*b as u32)) & 0xff) as usize;
        c = table[idx] ^ (c >> 8);
    }
    !c
}

fn zlib_stored(raw: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(raw.len() + raw.len() / 65535 * 5 + 6);
    out.push(0x78);
    out.push(0x01);

    let mut offset = 0usize;
    while offset < raw.len() {
        let remaining = raw.len() - offset;
        let block = remaining.min(65535);
        let final_flag = if offset + block == raw.len() { 1u8 } else { 0u8 };
        out.push(final_flag);

        let len = block as u16;
        let nlen = !len;
        out.extend_from_slice(&len.to_le_bytes());
        out.extend_from_slice(&nlen.to_le_bytes());
        out.extend_from_slice(&raw[offset..offset + block]);
        offset += block;
    }

    out.extend_from_slice(&adler32(raw).to_be_bytes());
    out
}

fn append_chunk(out: &mut Vec<u8>, chunk_type: &[u8; 4], payload: &[u8]) {
    out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    out.extend_from_slice(chunk_type);
    out.extend_from_slice(payload);

    let mut crc_input = Vec::with_capacity(4 + payload.len());
    crc_input.extend_from_slice(chunk_type);
    crc_input.extend_from_slice(payload);
    out.extend_from_slice(&crc32(&crc_input).to_be_bytes());
}

fn encode_png(width: usize, height: usize, rgb: &[u8]) -> Result<Vec<u8>, String> {
    if rgb.len() != width * height * 3 {
        return Err("invalid rgb payload".to_string());
    }
    let stride = width * 3;
    let mut raw = Vec::with_capacity(height * (stride + 1));
    for y in 0..height {
        raw.push(0);
        let start = y * stride;
        raw.extend_from_slice(&rgb[start..start + stride]);
    }

    let idat = zlib_stored(&raw);

    let mut out = Vec::new();
    out.extend_from_slice(&[137, 80, 78, 71, 13, 10, 26, 10]);

    let mut ihdr = [0u8; 13];
    ihdr[0..4].copy_from_slice(&(width as u32).to_be_bytes());
    ihdr[4..8].copy_from_slice(&(height as u32).to_be_bytes());
    ihdr[8] = 8;
    ihdr[9] = 2;
    append_chunk(&mut out, b"IHDR", &ihdr);
    append_chunk(&mut out, b"IDAT", &idat);
    append_chunk(&mut out, b"IEND", &[]);
    Ok(out)
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
    let (input, output, repeats) = parse_args().unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let data = fs::read(&input).unwrap_or_else(|e| {
        eprintln!("Error: read {input}: {e}");
        std::process::exit(1);
    });

    let (width, height, rgb) = parse_ppm(&data).unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let start = Instant::now();
    let mut png = Vec::new();
    for _ in 0..repeats {
        png = encode_png(width, height, &rgb).unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });
    }

    fs::write(&output, &png).unwrap_or_else(|e| {
        eprintln!("Error: write {output}: {e}");
        std::process::exit(1);
    });

    let stats = Stats {
        total_processed: (width * height * repeats) as u64,
        processing_ns: start.elapsed().as_nanos(),
    };
    print_stats(&stats);
}
