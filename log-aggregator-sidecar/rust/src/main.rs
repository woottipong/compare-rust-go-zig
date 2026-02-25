use clap::Parser;
use chrono::Utc;
use lazy_static::lazy_static;
use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use regex::Regex;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use axum::{extract::State, response::Json, routing::get, Router};
use std::net::SocketAddr;

// ============================================================================
// Data Structures
// ============================================================================

#[derive(Debug, Serialize, Deserialize)]
struct LogEntry {
    timestamp: String,
    level: String,
    app: String,
    pid: u32,
    message: String,
    source: String,
}

#[derive(Debug, Serialize)]
struct StatsResponse {
    total_processed: u64,
    total_bytes: u64,
    processing_time: f64,
    throughput: f64,
}

struct Stats {
    total_processed: AtomicU64,
    total_bytes: AtomicU64,
    start_time: Instant,
}

impl Stats {
    fn new() -> Self {
        Self {
            total_processed: AtomicU64::new(0),
            total_bytes: AtomicU64::new(0),
            start_time: Instant::now(),
        }
    }

    fn add_entry(&self, bytes: usize) {
        self.total_processed.fetch_add(1, Ordering::Relaxed);
        self.total_bytes.fetch_add(bytes as u64, Ordering::Relaxed);
    }

    fn get_stats(&self) -> StatsResponse {
        let total = self.total_processed.load(Ordering::Relaxed);
        let bytes = self.total_bytes.load(Ordering::Relaxed);
        let elapsed = self.start_time.elapsed().as_secs_f64();

        let throughput = if elapsed > 0.0 {
            total as f64 / elapsed
        } else {
            0.0
        };

        StatsResponse {
            total_processed: total,
            total_bytes: bytes,
            processing_time: elapsed,
            throughput,
        }
    }
}

// ============================================================================
// Configuration
// ============================================================================

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Config {
    /// Input log file to watch
    #[arg(short, long)]
    input: String,

    /// Output URL to send logs
    #[arg(short, long)]
    output: String,

    /// Buffer size for batch processing
    #[arg(short, long, default_value = "1000")]
    buffer: usize,

    /// Number of worker tasks
    #[arg(short, long, default_value = "4")]
    workers: usize,
}

fn print_config(config: &Config) {
    println!("── Configuration ─────────────────────");
    println!("  Input File : {}", config.input);
    println!("  Output URL : {}", config.output);
    println!("  Buffer     : {}", config.buffer);
    println!("  Workers    : {}", config.workers);
    println!();
}

// ============================================================================
// Log Parser
// ============================================================================

// Parse log format: "2023-03-15 10:30:45 INFO auth[5]: User 1234 login from 192.168.1.100"
lazy_static! {
    static ref LOG_REGEX: Regex = Regex::new(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) (\w+) (\w+)\[(\d+)\]: (.*)$").unwrap();
}

fn parse_log_line(line: &str, source: &str) -> LogEntry {
    match LOG_REGEX.captures(line) {
        Some(caps) => LogEntry {
            timestamp: caps.get(1).unwrap().as_str().to_string(),
            level: caps.get(2).unwrap().as_str().to_string(),
            app: caps.get(3).unwrap().as_str().to_string(),
            pid: caps.get(4).unwrap().as_str().parse().unwrap_or(0),
            message: caps.get(5).unwrap().as_str().to_string(),
            source: source.to_string(),
        },
        None => LogEntry {
            timestamp: Utc::now().format("%Y-%m-%d %H:%M:%S").to_string(),
            level: "UNKNOWN".to_string(),
            app: "raw".to_string(),
            pid: 0,
            message: line.trim().to_string(),
            source: source.to_string(),
        },
    }
}

// ============================================================================
// Forwarder
// ============================================================================

struct Forwarder {
    client: Client,
    output_url: String,
    buffer_tx: mpsc::Sender<Vec<u8>>,
    stats: Arc<Stats>,
    workers: Vec<JoinHandle<()>>,
}

impl Forwarder {
    fn new(output_url: String, buffer_size: usize, stats: Arc<Stats>, workers: usize) -> Self {
        let (buffer_tx, buffer_rx) = mpsc::channel(buffer_size);
        let client = Client::builder()
            .timeout(Duration::from_secs(5))
            .pool_max_idle_per_host(100)
            .pool_idle_timeout(Duration::from_secs(30))
            .build()
            .unwrap();

        let mut workers_handles = Vec::new();
        for i in 0..workers {
            let rx = buffer_rx.clone();
            let client = client.clone();
            let output_url = output_url.clone();
            
            let worker = tokio::spawn(async move {
                Self::worker(i, rx, &client, &output_url).await;
            });
            workers_handles.push(worker);
        }

        Self {
            client,
            output_url,
            buffer_tx,
            stats,
            workers: workers_handles,
        }
    }

    async fn worker(
        _id: usize,
        mut rx: mpsc::Receiver<Vec<u8>>,
        client: &Client,
        output_url: &str,
    ) {
        while let Some(batch) = rx.recv().await {
            if let Err(e) = Self::send_batch(client, output_url, batch).await {
                eprintln!("Failed to send batch: {}", e);
            }
        }
    }

    async fn send_batch(client: &Client, output_url: &str, batch: Vec<u8>) -> Result<(), Box<dyn std::error::Error>> {
        let response = client
            .post(output_url)
            .header("Content-Type", "application/json")
            .body(batch)
            .send()
            .await?;

        if response.status().is_success() {
            Ok(())
        } else {
            Err(format!("HTTP {}", response.status()).into())
        }
    }

    async fn send(&self, entry: &LogEntry) -> Result<(), Box<dyn std::error::Error>> {
        let data = serde_json::to_vec(entry)?;
        self.stats.add_entry(data.len());

        self.buffer_tx.send(data).await?;
        Ok(())
    }

    async fn stop(self) {
        drop(self.buffer_tx);
        for worker in self.workers {
            let _ = worker.await;
        }
    }
}

// ============================================================================
// File Watcher
// ============================================================================

async fn watch_file(
    config: Config,
    forwarder: Forwarder,
    stats: Arc<Stats>,
) -> Result<(), Box<dyn std::error::Error>> {
    let (tx, mut rx) = mpsc::channel::<()>();
    let input_path = Path::new(&config.input);
    let input_dir = input_path.parent().unwrap_or_else(|| Path::new("."));

    let mut watcher = RecommendedWatcher::new(
        move |res: Result<Event, notify::Error>| {
            match res {
                Ok(event) => {
                    if event.kind == EventKind::Modify {
                        if let Some(path) = event.paths.first() {
                            if path == input_path {
                                let _ = tx.blocking_send(());
                            }
                        }
                    }
                }
                Err(e) => eprintln!("Watch error: {:?}", e),
            }
        },
        Config::default(),
    )?;

    watcher.watch(input_dir, RecursiveMode::NonRecursive)?;

    // Process existing file first
    if let Err(e) = process_file(&config.input, &forwarder, &stats).await {
        eprintln!("Error processing initial file: {}", e);
    }

    println!("Watching {} for changes...", config.input);

    while rx.recv().await.is_some() {
        if let Err(e) = process_file(&config.input, &forwarder, &stats).await {
            eprintln!("Error processing file: {}", e);
        }
    }

    Ok(())
}

async fn process_file(
    filename: &str,
    forwarder: &Forwarder,
    stats: &Arc<Stats>,
) -> Result<(), Box<dyn std::error::Error>> {
    let file = File::open(filename)?;
    let reader = BufReader::new(file);
    let mut line_count = 0;

    for line in reader.lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }

        let entry = parse_log_line(&line, filename);
        if let Err(e) = forwarder.send(&entry).await {
            eprintln!("Forward error: {}", e);
        }

        line_count += 1;
    }

    if line_count > 0 {
        println!("Processed {} lines from {}", line_count, filename);
    }

    Ok(())
}

// ============================================================================
// Main
// ============================================================================

async fn health_handler() -> Json<serde_json::Value> {
    Json(serde_json::json!({"status": "ok"}))
}

async fn stats_handler(State(state): State<Arc<Stats>>) -> Json<StatsResponse> {
    Json(state.get_stats())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = Config::parse();
    print_config(&config);

    let stats = Arc::new(Stats::new());
    let forwarder = Forwarder::new(config.output.clone(), config.buffer, stats.clone(), config.workers);

    // Start HTTP server for stats
    let app = Router::new()
        .route("/health", get(health_handler))
        .route("/stats", get(stats_handler));
    
    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    let server = axum::Server::bind(&addr);
    let server_handle = tokio::spawn(server.serve(app.into_make_service()));

    // Start file watcher in background
    let stats_clone = stats.clone();
    let config_clone = config.clone();
    let forwarder_clone = forwarder;
    let watcher_handle = tokio::spawn(async move {
        if let Err(e) = watch_file(config_clone, forwarder_clone, stats_clone).await {
            eprintln!("File watcher error: {}", e);
        }
    });

    // Wait for either server or watcher
    tokio::select! {
        _ = server_handle => {},
        _ = watcher_handle => {},
    }

    Ok(())
}
