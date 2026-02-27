use std::sync::Arc;
use std::time::{Duration, Instant};
use axum::extract::ws::{Message, WebSocket};
use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;
use tokio::time::{interval, timeout};
use uuid::Uuid;

use crate::hub::{broadcast_except, Clients};
use crate::protocol::{
    Message as ChatMessage, MSG_CHAT, MSG_JOIN, MSG_LEAVE, MSG_PING, MSG_PONG,
    PING_INTERVAL_SEC, RATE_LIMIT_MSG_PER_SEC,
};
use crate::stats::Stats;

const TOKEN_MAX: u32 = RATE_LIMIT_MSG_PER_SEC as u32;
const PONG_TIMEOUT: Duration = Duration::from_secs(PING_INTERVAL_SEC * 2);
const PING_INTERVAL: Duration = Duration::from_secs(PING_INTERVAL_SEC);

struct RateLimiter {
    tokens: u32,
    last_refill: Instant,
}

impl RateLimiter {
    fn new() -> Self {
        Self { tokens: TOKEN_MAX, last_refill: Instant::now() }
    }

    fn allow(&mut self) -> bool {
        let elapsed = self.last_refill.elapsed().as_millis() as u32;
        let refill = elapsed * TOKEN_MAX / 1000;
        if refill > 0 {
            self.tokens = (self.tokens + refill).min(TOKEN_MAX);
            self.last_refill = Instant::now();
        }
        if self.tokens == 0 {
            return false;
        }
        self.tokens -= 1;
        true
    }
}

pub async fn handle_connection(
    socket: WebSocket,
    clients: Clients,
    stats: Arc<Stats>,
) {
    let id = Uuid::new_v4();
    let (tx, mut rx) = mpsc::channel::<Message>(64);

    stats.add_connection();

    let (mut sink, mut stream) = socket.split();

    // write task: forwards channel messages + sends pings on interval
    let write_task = tokio::spawn(async move {
        let mut ping_ticker = interval(PING_INTERVAL);
        ping_ticker.tick().await; // skip first immediate tick

        loop {
            tokio::select! {
                msg = rx.recv() => {
                    match msg {
                        Some(m) => {
                            if sink.send(m).await.is_err() { break; }
                        }
                        None => break,
                    }
                }
                _ = ping_ticker.tick() => {
                    let ts = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_millis() as i64;
                    let ping = serde_json::to_string(&ChatMessage {
                        msg_type: MSG_PING.to_string(),
                        room: None, user: None,
                        text: None, ts: Some(ts),
                    }).unwrap_or_default();
                    if sink.send(Message::Text(ping)).await.is_err() { break; }
                }
            }
        }
    });

    // read task: process incoming messages with pong timeout guard
    let mut limiter = RateLimiter::new();
    let mut user_id = String::new();

    loop {
        let next = timeout(PONG_TIMEOUT, stream.next()).await;
        let item = match next {
            Ok(Some(item)) => item,
            Ok(None) => break,         // client closed
            Err(_) => {
                eprintln!("client {id} pong timeout");
                break;
            }
        };

        let raw = match item {
            Ok(Message::Text(t)) => t,
            Ok(Message::Pong(_)) => continue, // keepalive pong
            Ok(Message::Close(_)) => break,
            Err(_) => break,
            _ => continue,
        };

        let msg: ChatMessage = match serde_json::from_str(&raw) {
            Ok(m) => m,
            Err(_) => continue, // ignore malformed JSON
        };

        match msg.msg_type.as_str() {
            MSG_JOIN => {
                user_id = msg.user.clone().unwrap_or_default();
                clients.write().await.insert(id, tx.clone());
            }
            MSG_CHAT => {
                if !limiter.allow() {
                    stats.add_dropped();
                    continue;
                }
                stats.add_message();
                broadcast_except(&clients, id, Message::Text(raw)).await;
            }
            MSG_PONG => {}
            MSG_LEAVE => break,
            _ => {}
        }
    }

    // cleanup
    clients.write().await.remove(&id);
    drop(write_task);
    stats.remove_connection();
    let _ = user_id;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rate_limit_drop() {
        let mut limiter = RateLimiter::new();
        let mut passed = 0u32;
        let mut dropped = 0u32;
        for _ in 0..20 {
            if limiter.allow() { passed += 1; } else { dropped += 1; }
        }
        assert_eq!(passed, TOKEN_MAX);
        assert_eq!(dropped, 20 - TOKEN_MAX);
    }

    #[test]
    fn test_rate_limit_refill() {
        let mut limiter = RateLimiter::new();
        for _ in 0..TOKEN_MAX { limiter.allow(); }
        assert!(!limiter.allow());
        limiter.last_refill = Instant::now() - Duration::from_secs(1);
        assert!(limiter.allow());
    }
}
