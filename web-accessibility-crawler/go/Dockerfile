FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/web-accessibility-crawler .

FROM debian:bookworm-slim
COPY --from=builder /out/web-accessibility-crawler /usr/local/bin/web-accessibility-crawler
ENTRYPOINT ["/usr/local/bin/web-accessibility-crawler"]
