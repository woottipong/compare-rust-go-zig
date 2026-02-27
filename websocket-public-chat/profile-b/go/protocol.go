package main

import (
	"encoding/json"
	"strings"
)

const (
	MsgJoin  = "join"
	MsgChat  = "chat"
	MsgPing  = "ping"
	MsgPong  = "pong"
	MsgLeave = "leave"
)

const (
	ChatPayloadSize    = 128
	Room               = "public"
	RateLimitMsgPerSec = 10
	PingIntervalSec    = 30
)

type Message struct {
	Type string `json:"type"`
	Room string `json:"room,omitempty"`
	User string `json:"user,omitempty"`
	Text string `json:"text,omitempty"`
	Ts   int64  `json:"ts,omitempty"`
}

func padToSize(text string, size int) string {
	if len(text) >= size {
		return text[:size]
	}
	return text + strings.Repeat(" ", size-len(text))
}

func marshalChatMessage(user, text string, ts int64) ([]byte, error) {
	msg := Message{
		Type: MsgChat,
		Room: Room,
		User: user,
		Text: text,
		Ts:   ts,
	}

	for {
		data, err := json.Marshal(msg)
		if err != nil {
			return nil, err
		}

		if len(data) == ChatPayloadSize {
			return data, nil
		}

		if len(data) < ChatPayloadSize {
			msg.Text += strings.Repeat(" ", ChatPayloadSize-len(data))
			continue
		}

		over := len(data) - ChatPayloadSize
		if over >= len(msg.Text) {
			msg.Text = ""
		} else {
			msg.Text = msg.Text[:len(msg.Text)-over]
		}
	}
}
