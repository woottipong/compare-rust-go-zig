FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/container-watchdog .

FROM debian:bookworm-slim
COPY --from=builder /out/container-watchdog /usr/local/bin/container-watchdog
ENTRYPOINT ["/usr/local/bin/container-watchdog"]
