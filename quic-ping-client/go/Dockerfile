FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/quic-ping-client .

FROM debian:bookworm-slim
COPY --from=builder /out/quic-ping-client /usr/local/bin/quic-ping-client
ENTRYPOINT ["/usr/local/bin/quic-ping-client"]
