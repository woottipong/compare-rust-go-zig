use regex::Regex;
use std::io::{self, BufRead, Read, Write};
use std::time::Instant;

struct MaskingRule {
    pattern: Regex,
    replacement: &'static str,
}

#[derive(Default)]
struct Stats {
    lines_processed: usize,
    bytes_read: u64,
    bytes_written: u64,
    matches_found: usize,
    start_time: Option<Instant>,
}

impl Stats {
    fn throughput_mbps(&self) -> f64 {
        let elapsed = self.start_time.map(|t| t.elapsed().as_secs_f64()).unwrap_or(0.0);
        if elapsed == 0.0 { return 0.0; }
        (self.bytes_read as f64) / 1024.0 / 1024.0 / elapsed
    }
    fn lines_per_sec(&self) -> f64 {
        let elapsed = self.start_time.map(|t| t.elapsed().as_secs_f64()).unwrap_or(0.0);
        if elapsed == 0.0 { return 0.0; }
        (self.lines_processed as f64) / elapsed
    }
}

fn create_rules() -> Vec<MaskingRule> {
    vec![
        MaskingRule { pattern: Regex::new(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}").unwrap(), replacement: "[EMAIL_MASKED]" },
        MaskingRule { pattern: Regex::new(r"\b(?:\+?1[-.]?)?\(?[0-9]{3}\)?[-.]?[0-9]{3}[-.]?[0-9]{4}\b").unwrap(), replacement: "[PHONE_MASKED]" },
        MaskingRule { pattern: Regex::new(r"\b[0-9]{13,16}\b").unwrap(), replacement: "[CC_MASKED]" },
        MaskingRule { pattern: Regex::new(r"\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b").unwrap(), replacement: "[SSN_MASKED]" },
        MaskingRule { pattern: Regex::new(r"(?i)(api[_-]?key|token|secret)[\s]*[:=][\s]*[a-zA-Z0-9_\-]{16,}").unwrap(), replacement: "[API_KEY_MASKED]" },
        MaskingRule { pattern: Regex::new(r"(?i)(password|pwd|pass)=[^&\s]+").unwrap(), replacement: "[PASSWORD_MASKED]" },
        MaskingRule { pattern: Regex::new(r"\b(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b").unwrap(), replacement: "[IP_MASKED]" },
    ]
}

fn mask_line(line: &str, rules: &[MaskingRule], stats: &mut Stats) -> String {
    let mut result = line.to_string();
    for rule in rules {
        let matches: Vec<_> = rule.pattern.find_iter(&result).collect();
        if !matches.is_empty() {
            stats.matches_found += matches.len();
            result = rule.pattern.replace_all(&result, rule.replacement).to_string();
        }
    }
    result
}

fn process_streams<R: Read, W: Write>(input: R, output: W, rules: &[MaskingRule], stats: &mut Stats) -> io::Result<()> {
    let reader = io::BufReader::with_capacity(64 * 1024, input);
    let mut writer = io::BufWriter::with_capacity(64 * 1024, output);
    stats.start_time = Some(Instant::now());

    for line_result in reader.lines() {
        let line = line_result?;
        stats.lines_processed += 1;
        stats.bytes_read += line.len() as u64 + 1;
        let masked = mask_line(&line, rules, stats);
        writer.write_all(masked.as_bytes())?;
        writer.write_all(b"\n")?;
        stats.bytes_written += masked.len() as u64 + 1;
    }
    writer.flush()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut input_path: Option<&str> = None;
    let mut output_path: Option<&str> = None;
    let mut show_stats = true;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-i" | "--input" => { i += 1; if i < args.len() { input_path = Some(&args[i]); } }
            "-o" | "--output" => { i += 1; if i < args.len() { output_path = Some(&args[i]); } }
            "--no-stats" => show_stats = false,
            "-h" | "--help" => {
                eprintln!("Usage: {} [options]", args[0]);
                eprintln!("  -i, --input <file>   Input file");
                eprintln!("  -o, --output <file>  Output file");
                std::process::exit(0);
            }
            _ => if !args[i].starts_with('-') && input_path.is_none() { input_path = Some(&args[i]); }
        }
        i += 1;
    }

    let input: Box<dyn Read> = if let Some(path) = input_path {
        Box::new(std::fs::File::open(path).unwrap_or_else(|e| { eprintln!("Error: {}", e); std::process::exit(1); }))
    } else {
        Box::new(io::stdin())
    };

    let output: Box<dyn Write> = if let Some(path) = output_path {
        Box::new(std::fs::File::create(path).unwrap_or_else(|e| { eprintln!("Error: {}", e); std::process::exit(1); }))
    } else {
        Box::new(io::stdout())
    };

    let rules = create_rules();
    let mut stats = Stats::default();

    if let Err(e) = process_streams(input, output, &rules, &mut stats) {
        eprintln!("Processing error: {}", e);
        std::process::exit(1);
    }

    if show_stats {
        let elapsed = stats.start_time.map(|t| t.elapsed().as_secs_f64()).unwrap_or(0.0);
        eprintln!("");
        eprintln!("--- Statistics ---");
        eprintln!("Lines processed: {}", stats.lines_processed);
        eprintln!("Bytes read: {}", stats.bytes_read);
        eprintln!("Matches found: {}", stats.matches_found);
        eprintln!("Processing time: {:.3}s", elapsed);
        eprintln!("Throughput: {:.2} MB/s", stats.throughput_mbps());
        eprintln!("Lines/sec: {:.0}", stats.lines_per_sec());
    }
}
