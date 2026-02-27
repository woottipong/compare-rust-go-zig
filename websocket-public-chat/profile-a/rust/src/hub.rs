use std::collections::HashMap;
use std::sync::Arc;
use axum::extract::ws::Message as WsMessage;
use tokio::sync::{mpsc, RwLock};
use uuid::Uuid;

/// Shared state: maps client ID → channel sender.
pub type Clients = Arc<RwLock<HashMap<Uuid, mpsc::Sender<WsMessage>>>>;

pub fn new_clients() -> Clients {
    Arc::new(RwLock::new(HashMap::new()))
}

/// Broadcast a message to all clients except the sender.
pub async fn broadcast_except(clients: &Clients, sender_id: Uuid, msg: WsMessage) {
    let guard = clients.read().await;
    for (id, tx) in guard.iter() {
        if *id == sender_id {
            continue;
        }
        // ignore send errors — client may have disconnected
        let _ = tx.send(msg.clone()).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_broadcast_to_others() {
        let clients = new_clients();

        let (tx1, mut rx1) = mpsc::channel(8);
        let (tx2, mut rx2) = mpsc::channel(8);
        let (tx3, mut rx3) = mpsc::channel(8);

        let id1 = Uuid::new_v4();
        let id2 = Uuid::new_v4();
        let id3 = Uuid::new_v4();

        {
            let mut w = clients.write().await;
            w.insert(id1, tx1);
            w.insert(id2, tx2);
            w.insert(id3, tx3);
        }

        let msg = WsMessage::Text(r#"{"type":"chat","text":"hello"}"#.to_string());
        broadcast_except(&clients, id1, msg.clone()).await;

        // c2 and c3 receive
        assert_eq!(rx2.recv().await.unwrap(), msg);
        assert_eq!(rx3.recv().await.unwrap(), msg);

        // c1 does NOT receive
        assert!(rx1.try_recv().is_err());
    }

    #[tokio::test]
    async fn test_state_cleanup() {
        let clients = new_clients();
        let id = Uuid::new_v4();
        let (tx, _rx) = mpsc::channel(8);

        clients.write().await.insert(id, tx);
        assert_eq!(clients.read().await.len(), 1);

        clients.write().await.remove(&id);
        assert_eq!(clients.read().await.len(), 0);
    }
}
