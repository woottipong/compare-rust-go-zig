use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::{Duration, Instant};

const PROTOCOL_NAME: &str = "BitTorrent protocol";
const HANDSHAKE_LEN: usize = 68;

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
    let host = args.get(1).cloned().unwrap_or_else(|| "host.docker.internal".to_string());
    let port = args
        .get(2)
        .map(|v| v.parse::<u16>())
        .transpose()
        .map_err(|_| "invalid port".to_string())?
        .unwrap_or(6881);
    let repeats = args
        .get(3)
        .map(|v| v.parse::<usize>())
        .transpose()
        .map_err(|_| "invalid repeats".to_string())?
        .unwrap_or(2000);
    if repeats == 0 {
        return Err("invalid repeats".to_string());
    }
    Ok((host, port, repeats))
}

fn build_handshake() -> [u8; HANDSHAKE_LEN] {
    let mut hs = [0u8; HANDSHAKE_LEN];
    hs[0] = PROTOCOL_NAME.len() as u8;
    hs[1..20].copy_from_slice(PROTOCOL_NAME.as_bytes());
    let mut info_hash = [0u8; 20];
    info_hash.copy_from_slice(&[
        0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x50,
        0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x60,
    ]);
    hs[28..48].copy_from_slice(&info_hash);
    hs[48..68].copy_from_slice(b"-RS0001-123456789012");
    hs
}

fn do_handshake(addr: &str, hs: &[u8; HANDSHAKE_LEN]) -> Result<(), String> {
    let socket_addr = addr
        .to_socket_addrs()
        .map_err(|e| format!("resolve address: {e}"))?
        .next()
        .ok_or_else(|| "no socket address".to_string())?;

    let mut stream = TcpStream::connect_timeout(&socket_addr, Duration::from_millis(200))
        .map_err(|e| format!("connect: {e}"))?;
    stream
        .set_read_timeout(Some(Duration::from_millis(500)))
        .map_err(|e| format!("set read timeout: {e}"))?;
    stream
        .set_write_timeout(Some(Duration::from_millis(500)))
        .map_err(|e| format!("set write timeout: {e}"))?;
    stream
        .write_all(hs)
        .map_err(|e| format!("write handshake: {e}"))?;

    let mut resp = [0u8; HANDSHAKE_LEN];
    stream
        .read_exact(&mut resp)
        .map_err(|e| format!("read handshake: {e}"))?;

    if resp[0] != PROTOCOL_NAME.len() as u8 || &resp[1..20] != PROTOCOL_NAME.as_bytes() {
        return Err("invalid handshake response".to_string());
    }

    Ok(())
}

fn print_stats(s: &Stats) {
    println!("--- Statistics ---");
    println!("Total processed: {}", s.total_processed);
    println!("Processing time: {:.3}s", s.processing_ns as f64 / 1_000_000_000.0);
    println!("Average latency: {:.6}ms", s.avg_latency_ms());
    println!("Throughput: {:.2} items/sec", s.throughput());
}

fn main() {
    let (host, port, repeats) = parse_args().unwrap_or_else(|e| {
        eprintln!("Error: {e}");
        std::process::exit(1);
    });

    let addr = format!("{host}:{port}");
    let handshake = build_handshake();
    let start = Instant::now();

    for _ in 0..repeats {
        if let Err(err) = do_handshake(&addr, &handshake) {
            eprintln!("Error: {err}");
            std::process::exit(1);
        }
    }

    let s = Stats {
        total_processed: repeats as u64,
        processing_ns: start.elapsed().as_nanos(),
    };
    print_stats(&s);
}
