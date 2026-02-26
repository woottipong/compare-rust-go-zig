FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/tiny-health-check-agent .

FROM debian:bookworm-slim
COPY --from=builder /out/tiny-health-check-agent /usr/local/bin/tiny-health-check-agent
ENTRYPOINT ["/usr/local/bin/tiny-health-check-agent"]
