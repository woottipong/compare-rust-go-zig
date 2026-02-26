FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/custom-bittorrent-client .

FROM debian:bookworm-slim
COPY --from=builder /out/custom-bittorrent-client /usr/local/bin/custom-bittorrent-client
ENTRYPOINT ["/usr/local/bin/custom-bittorrent-client"]
