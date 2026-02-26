FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/in-memory-kv-store .

FROM debian:bookworm-slim
COPY --from=builder /out/in-memory-kv-store /usr/local/bin/in-memory-kv-store
ENTRYPOINT ["/usr/local/bin/in-memory-kv-store"]
