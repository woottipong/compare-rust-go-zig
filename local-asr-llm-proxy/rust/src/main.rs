use axum::{
    extract::State,
    http::StatusCode,
    response::Json,
    routing::{get, post},
    Router,
};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{mpsc, oneshot};
use uuid::Uuid;

// ============================================================================
// Data Structures
// ============================================================================

#[derive(Debug, Serialize, Deserialize)]
struct TranscriptionRequest {
    audio_data: String,
    format: String,
    language: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct TranscriptionResponse {
    job_id: String,
    status: String,
    transcription: String,
    processing_time_ms: u64,
}

#[derive(Debug, Serialize, Deserialize)]
struct BackendResponse {
    transcription: String,
    confidence: f64,
    processing_time_ms: u64,
}

#[derive(Debug, Serialize)]
struct StatsResponse {
    total_processed: u64,
    processing_time_s: f64,
    average_latency_ms: f64,
    throughput: f64,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
}

struct Job {
    id: String,
    audio_data: String,
    format: String,
    language: String,
    response_tx: oneshot::Sender<Result<TranscriptionResponse, String>>,
}

struct Stats {
    total_processed: AtomicU64,
    total_latency_ns: AtomicU64,
    start_time: Instant,
}

impl Stats {
    fn new() -> Self {
        Self {
            total_processed: AtomicU64::new(0),
            total_latency_ns: AtomicU64::new(0),
            start_time: Instant::now(),
        }
    }

    fn add_request(&self, latency_ns: u64) {
        self.total_processed.fetch_add(1, Ordering::Relaxed);
        self.total_latency_ns.fetch_add(latency_ns, Ordering::Relaxed);
    }

    fn get_stats(&self) -> StatsResponse {
        let total = self.total_processed.load(Ordering::Relaxed);
        let latency_ns = self.total_latency_ns.load(Ordering::Relaxed);
        let elapsed = self.start_time.elapsed().as_secs_f64();

        let avg_latency_ms = if total > 0 {
            (latency_ns / total) as f64 / 1_000_000.0
        } else {
            0.0
        };

        let throughput = if elapsed > 0.0 {
            total as f64 / elapsed
        } else {
            0.0
        };

        StatsResponse {
            total_processed: total,
            processing_time_s: elapsed,
            average_latency_ms: avg_latency_ms,
            throughput,
        }
    }
}

struct AppState {
    job_tx: mpsc::Sender<Job>,
    stats: Arc<Stats>,
}

// ============================================================================
// Main
// ============================================================================

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    let listen_addr = args.get(1).map(|s| s.as_str()).unwrap_or("0.0.0.0:8080");
    let backend_url = args.get(2).map(|s| s.as_str()).unwrap_or("http://localhost:3000");

    let worker_count = num_cpus::get();
    let queue_size = 1000;

    print_config(listen_addr, backend_url, worker_count, queue_size);

    let (job_tx, job_rx) = mpsc::channel::<Job>(queue_size);
    let stats = Arc::new(Stats::new());

    // Start workers
    for worker_id in 0..worker_count {
        let job_rx = job_rx.clone();
        let backend_url = backend_url.to_string();
        let stats = stats.clone();

        tokio::spawn(async move {
            worker(worker_id, job_rx, &backend_url, stats).await;
        });
    }

    let state = Arc::new(AppState { job_tx, stats });

    let app = Router::new()
        .route("/transcribe", post(handle_transcribe))
        .route("/health", get(handle_health))
        .route("/stats", get(handle_stats))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(listen_addr).await.unwrap();
    println!("Server listening on {}", listen_addr);

    axum::serve(listener, app).await.unwrap();
}

fn print_config(listen_addr: &str, backend_url: &str, worker_count: usize, queue_size: usize) {
    println!("── Configuration ─────────────────────");
    println!("  Listen Addr : {}", listen_addr);
    println!("  Backend URL : {}", backend_url);
    println!("  Workers     : {}", worker_count);
    println!("  Queue Size  : {}", queue_size);
    println!();
}

// ============================================================================
// Worker
// ============================================================================

async fn worker(
    worker_id: usize,
    mut job_rx: mpsc::Receiver<Job>,
    backend_url: &str,
    stats: Arc<Stats>,
) {
    let client = Client::builder()
        .timeout(Duration::from_secs(3))
        .pool_max_idle_per_host(10)
        .build()
        .unwrap();

    while let Some(job) = job_rx.recv().await {
        let start = Instant::now();

        let result = forward_to_backend(&client, backend_url, &job).await;

        // Record stats
        let latency_ns = start.elapsed().as_nanos() as u64;
        stats.add_request(latency_ns);

        // Send response
        let response = match result {
            Ok(resp) => Ok(resp),
            Err(e) => Err(format!("Backend error: {}", e)),
        };

        let _ = job.response_tx.send(response);
    }
}

async fn forward_to_backend(
    client: &Client,
    backend_url: &str,
    job: &Job,
) -> Result<TranscriptionResponse, Box<dyn std::error::Error>> {
    let req_body = serde_json::json!({
        "audio_data": job.audio_data,
        "format": job.format,
        "language": job.language,
    });

    let response = client
        .post(format!("{}/transcribe", backend_url))
        .json(&req_body)
        .send()
        .await?;

    let backend_resp: BackendResponse = response.json().await?;

    Ok(TranscriptionResponse {
        job_id: job.id.clone(),
        status: "completed".to_string(),
        transcription: backend_resp.transcription,
        processing_time_ms: backend_resp.processing_time_ms,
    })
}

// ============================================================================
// HTTP Handlers
// ============================================================================

async fn handle_transcribe(
    State(state): State<Arc<AppState>>,
    Json(req): Json<TranscriptionRequest>,
) -> Result<Json<TranscriptionResponse>, (StatusCode, String)> {
    let (response_tx, response_rx) = oneshot::channel();

    let job = Job {
        id: Uuid::new_v4().to_string(),
        audio_data: req.audio_data,
        format: req.format,
        language: req.language,
        response_tx,
    };

    // Try to enqueue job
    if state.job_tx.send(job).await.is_err() {
        return Err((StatusCode::SERVICE_UNAVAILABLE, "Queue full".to_string()));
    }

    // Wait for response with timeout
    match tokio::time::timeout(Duration::from_secs(5), response_rx).await {
        Ok(Ok(Ok(resp))) => Ok(Json(resp)),
        Ok(Ok(Err(e))) => Err((StatusCode::INTERNAL_SERVER_ERROR, e)),
        Ok(Err(_)) => Err((StatusCode::INTERNAL_SERVER_ERROR, "Channel closed".to_string())),
        Err(_) => Err((StatusCode::GATEWAY_TIMEOUT, "Request timeout".to_string())),
    }
}

async fn handle_health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok".to_string(),
    })
}

async fn handle_stats(State(state): State<Arc<AppState>>) -> Json<StatsResponse> {
    Json(state.stats.get_stats())
}
