FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/tcp-port-scanner .

FROM debian:bookworm-slim
COPY --from=builder /out/tcp-port-scanner /usr/local/bin/tcp-port-scanner
ENTRYPOINT ["/usr/local/bin/tcp-port-scanner"]
