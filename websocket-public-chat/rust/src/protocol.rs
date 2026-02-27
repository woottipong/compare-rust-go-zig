use serde::{Deserialize, Serialize};

pub const MSG_JOIN: &str = "join";
pub const MSG_CHAT: &str = "chat";
pub const MSG_PING: &str = "ping";
pub const MSG_PONG: &str = "pong";
pub const MSG_LEAVE: &str = "leave";

pub const CHAT_PAYLOAD_SIZE: usize = 128;
pub const ROOM: &str = "public";
pub const RATE_LIMIT_MSG_PER_SEC: usize = 10;
pub const PING_INTERVAL_SEC: u64 = 30;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Message {
    #[serde(rename = "type")]
    pub msg_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub room: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ts: Option<i64>,
}

pub fn pad_to_size(text: &str, size: usize) -> String {
    if text.len() >= size {
        return text[..size].to_string();
    }

    let mut padded = String::with_capacity(size);
    padded.push_str(text);
    padded.push_str(&" ".repeat(size - text.len()));
    padded
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pad_to_size() {
        let padded = pad_to_size("hello", 128);
        assert_eq!(padded.len(), 128);
    }

    #[test]
    fn test_serde_roundtrip() {
        let msg = Message {
            msg_type: MSG_CHAT.to_string(),
            room: Some(ROOM.to_string()),
            user: Some("client-01".to_string()),
            text: Some("hello".to_string()),
            ts: Some(1_700_000_000),
        };

        let json = serde_json::to_string(&msg).expect("serialize message");
        let parsed: Message = serde_json::from_str(&json).expect("deserialize message");

        assert_eq!(parsed, msg);
    }
}
