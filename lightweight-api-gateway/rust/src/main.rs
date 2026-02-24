use axum::{
    extract::{Request, State},
    http::StatusCode,
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::get,
    Router,
};
use dashmap::DashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tower::Layer;

#[derive(Clone)]
struct AppState {
    target_url: String,
    rate_limiter: Arc<RateLimiter>,
}

struct RateLimiter {
    clients: DashMap<String, ClientState>,
}

struct ClientState {
    count: u32,
    last_reset: Instant,
}

impl RateLimiter {
    fn new() -> Self {
        Self {
            clients: DashMap::new(),
        }
    }

    fn allow(&self, client_ip: &str, limit: u32, window: Duration) -> bool {
        let now = Instant::now();
        
        let mut entry = self.clients.entry(client_ip.to_string()).or_insert(ClientState {
            count: 0,
            last_reset: now,
        });

        if now.duration_since(entry.last_reset) >= window {
            entry.count = 0;
            entry.last_reset = now;
        }

        if entry.count >= limit {
            return false;
        }

        entry.count += 1;
        true
    }
}

async fn jwt_middleware(
    State(state): State<AppState>,
    request: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    // Skip JWT for public endpoints
    if request.uri().path().starts_with("/public/") {
        return Ok(next.run(request).await);
    }

    let auth_header = request
        .headers()
        .get("authorization")
        .and_then(|h| h.to_str().ok());

    if let Some(auth_header) = auth_header {
        if let Some(token) = auth_header.strip_prefix("Bearer ") {
            // Simple JWT validation (for demo - in production use proper validation)
            if token == "valid-test-token" {
                return Ok(next.run(request).await);
            }
        }
    }

    Err(StatusCode::UNAUTHORIZED)
}

async fn rate_limit_middleware(
    State(state): State<AppState>,
    request: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let client_ip = request
        .extensions()
        .get::<SocketAddr>()
        .map(|addr| addr.ip().to_string())
        .unwrap_or_else(|| "unknown".to_string());

    if !state.rate_limiter.allow(&client_ip, 100, Duration::from_secs(60)) {
        return Err(StatusCode::TOO_MANY_REQUESTS);
    }

    Ok(next.run(request).await)
}

async fn proxy_handler(
    State(state): State<AppState>,
    request: Request,
) -> impl IntoResponse {
    // For demo purposes, return a simple response instead of actual proxy
    let path = request.uri().path();
    let method = request.method().to_string();
    
    let response = format!(
        r#"{{
        "message": "Gateway received request",
        "method": "{}",
        "path": "{}",
        "target": "{}",
        "timestamp": {}
    }}"#,
        method,
        path,
        state.target_url,
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs()
    );

    (StatusCode::OK, response)
}

async fn health_check() -> &'static str {
    "OK"
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 {
        eprintln!("Usage: {} <listen_addr> <target_url>", args[0]);
        eprintln!("Example: {} :8080 http://localhost:3000", args[0]);
        std::process::exit(1);
    }

    let addr_str = if args[1].starts_with(':') {
        format!("127.0.0.1{}", args[1])
    } else {
        args[1].clone()
    };
    let listen_addr: SocketAddr = addr_str.parse().expect("Invalid listen address");
    let target_url = args[2].clone();

    let rate_limiter = Arc::new(RateLimiter::new());

    let app_state = AppState {
        target_url,
        rate_limiter,
    };

    let target_url_for_print = app_state.target_url.clone();
    
    let app = Router::new()
        .route("/health", get(health_check))
        .fallback(proxy_handler)
        .layer(middleware::from_fn_with_state(app_state.clone(), rate_limit_middleware))
        .layer(middleware::from_fn_with_state(app_state.clone(), jwt_middleware))
        .with_state(app_state);

    println!("Starting gateway on {} -> {}", listen_addr, target_url_for_print);

    let listener = tokio::net::TcpListener::bind(listen_addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
