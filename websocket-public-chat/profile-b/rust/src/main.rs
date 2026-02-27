mod hub;
mod client;
mod protocol;
mod stats;

use std::sync::Arc;
use std::time::Duration;
use clap::Parser;
use tokio::net::TcpListener;


use hub::new_clients;
use client::handle_connection;
use stats::Stats;

#[derive(Parser)]
#[command(name = "websocket-public-chat")]
struct Cli {
    #[arg(long, default_value = "8080")]
    port: u16,
    /// Run duration in seconds (0 = run until interrupted)
    #[arg(long, default_value = "0")]
    duration: u64,
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    let addr = format!("0.0.0.0:{}", cli.port);

    let listener = TcpListener::bind(&addr).await.expect("bind failed");
    eprintln!("websocket-public-chat: listening on {addr}");

    let clients = new_clients();
    let stats = Arc::new(Stats::new());

    let stats_clone = Arc::clone(&stats);
    let clients_clone = Arc::clone(&clients);

    let serve = async move {
        loop {
            match listener.accept().await {
                Ok((stream, _)) => {
                    let c = Arc::clone(&clients_clone);
                    let s = Arc::clone(&stats_clone);
                    tokio::spawn(handle_connection(stream, c, s));
                }
                Err(e) => eprintln!("accept error: {e}"),
            }
        }
    };

    if cli.duration > 0 {
        tokio::select! {
            _ = serve => {}
            _ = tokio::time::sleep(Duration::from_secs(cli.duration)) => {}
        }
    } else {
        serve.await;
    }

    stats.print_stats();
}
