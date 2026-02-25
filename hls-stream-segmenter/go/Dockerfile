FROM golang:1.25-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libavformat-dev libavcodec-dev libavutil-dev libswscale-dev gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=1 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/segmenter-go .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libavformat59 libavcodec59 libavutil57 libswscale6 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /out/segmenter-go /usr/local/bin/segmenter-go
ENTRYPOINT ["segmenter-go"]
