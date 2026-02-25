FROM golang:1.23-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/asr-proxy .

FROM debian:bookworm-slim
COPY --from=builder /out/asr-proxy /usr/local/bin/asr-proxy
ENTRYPOINT ["asr-proxy"]
CMD ["0.0.0.0:8080", "http://localhost:3000"]
