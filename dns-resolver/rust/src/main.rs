use std::net::UdpSocket;
use std::time::{Duration, Instant};

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

fn parse_args() -> Result<(String, u16, usize), String> {
    let args: Vec<String> = std::env::args().collect();
    let host = if args.len() > 1 {
        args[1].clone()
    } else {
        "host.docker.internal".to_string()
    };
    let port = if args.len() > 2 {
        args[2]
            .parse::<u16>()
            .map_err(|_| "port must be positive integer".to_string())?
    } else {
        53535
    };
    let repeats = if args.len() > 3 {
        args[3]
            .parse::<usize>()
            .map_err(|_| "repeats must be positive integer".to_string())?
    } else {
        2000
    };
    if repeats == 0 {
        return Err("repeats must be positive integer".to_string());
    }
    Ok((host, port, repeats))
}

fn split_labels(name: &str) -> Vec<&str> {
    name.split('.').filter(|s| !s.is_empty()).collect()
}

fn build_query(id: u16, name: &str) -> Vec<u8> {
    let mut q = vec![0u8; 12];
    q[0..2].copy_from_slice(&id.to_be_bytes());
    q[2..4].copy_from_slice(&0x0100u16.to_be_bytes());
    q[4..6].copy_from_slice(&1u16.to_be_bytes());

    for label in split_labels(name) {
        q.push(label.len() as u8);
        q.extend_from_slice(label.as_bytes());
    }
    q.push(0);
    q.extend_from_slice(&1u16.to_be_bytes());
    q.extend_from_slice(&1u16.to_be_bytes());
    q
}

fn read_name(msg: &[u8], mut off: usize) -> Result<usize, String> {
    loop {
        if off >= msg.len() {
            return Err("invalid name offset".to_string());
        }
        let l = msg[off] as usize;
        off += 1;
        if l == 0 {
            return Ok(off);
        }
        if l & 0xC0 == 0xC0 {
            if off >= msg.len() {
                return Err("invalid compressed name".to_string());
            }
            return Ok(off + 1);
        }
        off += l;
    }
}

fn parse_a_record_count(msg: &[u8]) -> Result<usize, String> {
    if msg.len() < 12 {
        return Err("short dns message".to_string());
    }
    let qd = u16::from_be_bytes([msg[4], msg[5]]) as usize;
    let an = u16::from_be_bytes([msg[6], msg[7]]) as usize;
    let mut off = 12usize;

    for _ in 0..qd {
        off = read_name(msg, off)?;
        off += 4;
    }

    let mut count = 0usize;
    for _ in 0..an {
        off = read_name(msg, off)?;
        if off + 10 > msg.len() {
            return Err("invalid rr".to_string());
        }
        let type_code = u16::from_be_bytes([msg[off], msg[off + 1]]);
        let rdlen = u16::from_be_bytes([msg[off + 8], msg[off + 9]]) as usize;
        off += 10;
        if off + rdlen > msg.len() {
            return Err("invalid rdata".to_string());
        }
        if type_code == 1 && rdlen == 4 {
            count += 1;
        }
        off += rdlen;
    }
    Ok(count)
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
    let (host, port, repeats) = parse_args().unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let socket = UdpSocket::bind("0.0.0.0:0").unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });
    socket
        .connect(format!("{host}:{port}"))
        .unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });
    socket
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });

    let start = Instant::now();
    let mut buf = [0u8; 512];
    for i in 0..repeats {
        let q = build_query((i + 1) as u16, "example.com");
        socket.send(&q).unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });
        let n = socket.recv(&mut buf).unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });
        parse_a_record_count(&buf[..n]).unwrap_or_else(|e| {
            eprintln!("Error: {e}");
            std::process::exit(1);
        });
    }

    let stats = Stats {
        total_processed: repeats as u64,
        processing_ns: start.elapsed().as_nanos(),
    };
    print_stats(&stats);
}
