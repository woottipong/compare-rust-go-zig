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

struct Stats {
    total_processed: AtomicU64,
    total_latency_ns: AtomicU64,
    start_time: Instant,
    // Shared HTTP client for connection pooling
    client: reqwest::Client,
}

impl Stats {
    fn new() -> Self {
        Self {
            total_processed: AtomicU64::new(0),
            total_latency_ns: AtomicU64::new(0),
            start_time: Instant::now(),
            client: Client::builder()
                .timeout(Duration::from_secs(3))
                .pool_max_idle_per_host(100)
                .pool_idle_timeout(Duration::from_secs(30))
                .build()
                .unwrap(),
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

    fn get_client(&self) -> &Client {
        &self.client
    }
}

type AppState = Arc<Stats>;

// ============================================================================
// Main
// ============================================================================

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    let listen_addr = args.get(1).map(|s| s.as_str()).unwrap_or("0.0.0.0:8080");
    let backend_url = args.get(2).map(|s| s.as_str()).unwrap_or("http://localhost:3000");

    print_config(listen_addr, backend_url);

    let state = Arc::new(Stats::new());

    // Store backend URL in a static for the handler
    // This is a hack to avoid passing it through the state
    BACKEND_URL.set(backend_url.to_string()).ok();

    let app = Router::new()
        .route("/transcribe", post(handle_transcribe))
        .route("/health", get(handle_health))
        .route("/stats", get(handle_stats))
        .with_state(state.clone());

    let listener = tokio::net::TcpListener::bind(listen_addr).await.unwrap();
    println!("Server listening on {}", listen_addr);

    axum::serve(listener, app).await.unwrap();
}

// Global backend URL - set once at startup
static BACKEND_URL: std::sync::OnceLock<String> = std::sync::OnceLock::new();

fn print_config(listen_addr: &str, backend_url: &str) {
    println!("── Configuration ─────────────────────");
    println!("  Listen Addr : {}", listen_addr);
    println!("  Backend URL : {}", backend_url);
    println!("  Mode        : Direct (no worker pool)");
    println!();
}

// ============================================================================
// HTTP Handlers
// ============================================================================

async fn handle_transcribe(
    State(state): State<AppState>,
    Json(req): Json<TranscriptionRequest>,
) -> Result<Json<TranscriptionResponse>, (StatusCode, String)> {
    let start = Instant::now();
    
    let backend_url = BACKEND_URL.get().unwrap();

    // Forward to backend directly using shared connection pool
    let result = forward_to_backend(state.get_client(), backend_url, &req).await;

    // Record stats
    let latency_ns = start.elapsed().as_nanos() as u64;
    state.add_request(latency_ns);

    match result {
        Ok(resp) => Ok(Json(resp)),
        Err(e) => Err((StatusCode::BAD_GATEWAY, format!("Backend error: {}", e))),
    }
}

async fn forward_to_backend(
    client: &Client,
    backend_url: &str,
    req: &TranscriptionRequest,
) -> Result<TranscriptionResponse, Box<dyn std::error::Error + Send + Sync>> {
    let req_body = serde_json::json!({
        "audio_data": req.audio_data,
        "format": req.format,
        "language": req.language,
    });

    let response = client
        .post(format!("{}/transcribe", backend_url))
        .json(&req_body)
        .send()
        .await?;

    let backend_resp: BackendResponse = response.json().await?;

    Ok(TranscriptionResponse {
        job_id: Uuid::new_v4().to_string(),
        status: "completed".to_string(),
        transcription: backend_resp.transcription,
        processing_time_ms: backend_resp.processing_time_ms,
    })
}

async fn handle_health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok".to_string(),
    })
}

async fn handle_stats(State(state): State<AppState>) -> Json<StatsResponse> {
    Json(state.get_stats())
}
