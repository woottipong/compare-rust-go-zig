FROM golang:1.23-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libavformat-dev \
    libavcodec-dev \
    libavutil-dev \
    libswscale-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN go build -o /out/segmenter-go .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libavformat60 libavcodec60 libavutil58 libswscale7 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/segmenter-go /usr/local/bin/segmenter-go
ENTRYPOINT ["segmenter-go"]
