use anyhow::Result;
use clap::Parser;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::RwLock;

const DEFAULT_PORT: u16 = 8080;
const DEFAULT_BACKENDS: &str = "localhost:3001,localhost:3002,localhost:3003";

struct Backend {
    host: String,
    port: u16,
    healthy: bool,
}

#[derive(Clone)]
struct LoadBalancer {
    backends: Arc<RwLock<Vec<Backend>>>,
    index: Arc<RwLock<usize>>,
}

impl LoadBalancer {
    fn new(addrs: Vec<(String, u16)>) -> Self {
        let backends = addrs
            .into_iter()
            .map(|(host, port)| Backend { host, port, healthy: true })
            .collect();
        Self {
            backends: Arc::new(RwLock::new(backends)),
            index: Arc::new(RwLock::new(0)),
        }
    }

    async fn get_backend(&self) -> Option<(String, u16)> {
        let backends = self.backends.read().await;
        let len = backends.len();
        if len == 0 {
            return None;
        }
        let mut idx = self.index.write().await;
        for _ in 0..len {
            let cur = *idx % len;
            *idx += 1;
            if backends[cur].healthy {
                return Some((backends[cur].host.clone(), backends[cur].port));
            }
        }
        None
    }

    fn start_health_checker(&self) {
        let lb = self.clone();
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(2)).await;
                let backends = lb.backends.read().await;
                let mut results = Vec::with_capacity(backends.len());
                for (i, b) in backends.iter().enumerate() {
                    let addr = format!("{}:{}", b.host, b.port);
                    let ok = tokio::net::TcpStream::connect(&addr).await.is_ok();
                    results.push((i, ok));
                }
                drop(backends);
                let mut backends = lb.backends.write().await;
                for (i, ok) in results {
                    backends[i].healthy = ok;
                }
            }
        });
    }
}

fn parse_backends(s: &str) -> Vec<(String, u16)> {
    s.split(',')
        .filter_map(|part| {
            let part = part.trim();
            let (host, port_str) = part.rsplit_once(':')?;
            let port = port_str.parse::<u16>().ok()?;
            Some((host.to_string(), port))
        })
        .collect()
}

async fn proxy_tcp(backend: (String, u16), request_bytes: &[u8]) -> Result<Vec<u8>> {
    let addr = format!("{}:{}", backend.0, backend.1);
    let mut stream = tokio::net::TcpStream::connect(addr).await?;
    stream.write_all(request_bytes).await?;
    stream.shutdown().await?;
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await?;
    Ok(buf)
}

async fn handle_client(mut client: tokio::net::TcpStream, lb: LoadBalancer) {
    let mut buf = [0u8; 8192];
    let n = match client.read(&mut buf).await {
        Ok(n) if n > 0 => n,
        _ => return,
    };

    let backend = match lb.get_backend().await {
        Some(b) => b,
        None => {
            let _ = client
                .write_all(b"HTTP/1.1 503 Service Unavailable\r\nContent-Length: 19\r\n\r\nNo healthy backends")
                .await;
            return;
        }
    };

    match proxy_tcp(backend, &buf[..n]).await {
        Ok(resp) => {
            let _ = client.write_all(&resp).await;
        }
        Err(_) => {
            let _ = client
                .write_all(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 12\r\n\r\nBad Gateway")
                .await;
        }
    }
}

#[derive(Parser)]
#[command(name = "hprp")]
struct Args {
    #[arg(long, default_value_t = DEFAULT_PORT)]
    port: u16,
    #[arg(long, default_value = DEFAULT_BACKENDS)]
    backends: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    let backends = parse_backends(&args.backends);
    if backends.is_empty() {
        anyhow::bail!("No backends specified");
    }

    let lb = LoadBalancer::new(backends);
    lb.start_health_checker();

    let addr = SocketAddr::from(([0, 0, 0, 0], args.port));
    let listener = TcpListener::bind(addr).await?;

    println!("Reverse Proxy starting on {}", addr);
    println!("Backends: {}", args.backends);

    loop {
        let (stream, _) = listener.accept().await?;
        let lb = lb.clone();
        tokio::spawn(async move {
            handle_client(stream, lb).await;
        });
    }
}
