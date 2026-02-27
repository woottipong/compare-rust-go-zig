mod hub;
mod client;
mod protocol;
mod stats;

use std::sync::Arc;
use std::time::Duration;
use axum::{
    extract::{State, WebSocketUpgrade},
    response::IntoResponse,
    routing::get,
    Router,
};
use clap::Parser;
use tokio::net::TcpListener;


use hub::new_clients;
use client::handle_connection;
use stats::Stats;

#[derive(Clone)]
struct AppState {
    clients: hub::Clients,
    stats: Arc<Stats>,
}

#[derive(Parser)]
#[command(name = "websocket-public-chat-profile-a")]
struct Cli {
    #[arg(long, default_value = "8080")]
    port: u16,
    /// Run duration in seconds (0 = run until interrupted)
    #[arg(long, default_value = "0")]
    duration: u64,
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| {
        handle_connection(socket, state.clients, state.stats)
    })
}

async fn health_handler() -> &'static str {
    "ok"
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    let addr = format!("0.0.0.0:{}", cli.port);

    let state = AppState {
        clients: new_clients(),
        stats: Arc::new(Stats::new()),
    };

    let app = Router::new()
        .route("/ws", get(ws_handler))
        .route("/health", get(health_handler))
        .with_state(state.clone());

    let listener = TcpListener::bind(&addr).await.expect("bind failed");
    eprintln!("websocket-public-chat (profile-a): listening on {addr}");

    let serve = axum::serve(listener, app);

    if cli.duration > 0 {
        tokio::select! {
            _ = serve => {}
            _ = tokio::time::sleep(Duration::from_secs(cli.duration)) => {}
        }
    } else {
        serve.await.expect("server error");
    }

    state.stats.print_stats();
}
