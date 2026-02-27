package main

import (
	"encoding/json"
	"testing"
)

func TestPadToSize(t *testing.T) {
	got := padToSize("hello", 128)
	if len(got) != 128 {
		t.Fatalf("expected length 128, got %d", len(got))
	}
}

func TestMarshalChat(t *testing.T) {
	data, err := marshalChatMessage("client-01", "hello", 1700000000)
	if err != nil {
		t.Fatalf("marshalChatMessage failed: %v", err)
	}

	if len(data) != ChatPayloadSize {
		t.Fatalf("expected payload size %d, got %d", ChatPayloadSize, len(data))
	}

	var msg Message
	if err := json.Unmarshal(data, &msg); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}

	if msg.Type != MsgChat {
		t.Fatalf("expected type %q, got %q", MsgChat, msg.Type)
	}
	if msg.User != "client-01" {
		t.Fatalf("expected user client-01, got %q", msg.User)
	}
	if msg.Room != Room {
		t.Fatalf("expected room %q, got %q", Room, msg.Room)
	}
}
