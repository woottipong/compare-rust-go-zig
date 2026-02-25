# Stage 1: builder
FROM golang:1.25-bookworm AS builder

WORKDIR /build

# Copy go.mod first for module detection
COPY go.mod ./

# Copy source
COPY main.go ./

# Build
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o vdi-go .

# Stage 2: runtime
FROM debian:bookworm-slim

WORKDIR /app

COPY --from=builder /build/vdi-go /usr/local/bin/vdi-go

RUN mkdir -p /data

ENTRYPOINT ["vdi-go"]
CMD ["/data/test.json"]
