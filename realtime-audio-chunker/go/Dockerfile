# Stage 1: builder
FROM golang:1.23-bookworm AS builder

WORKDIR /app
COPY go.mod ./
COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/realtime-audio-chunker-go .

# Stage 2: runtime
FROM debian:bookworm-slim
COPY --from=builder /out/realtime-audio-chunker-go /usr/local/bin/realtime-audio-chunker-go

ENTRYPOINT ["realtime-audio-chunker-go"]
