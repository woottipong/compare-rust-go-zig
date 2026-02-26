FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/dns-resolver .

FROM debian:bookworm-slim
COPY --from=builder /out/dns-resolver /usr/local/bin/dns-resolver
ENTRYPOINT ["/usr/local/bin/dns-resolver"]
