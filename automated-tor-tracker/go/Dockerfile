FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/automated-tor-tracker .

FROM debian:bookworm-slim
COPY --from=builder /out/automated-tor-tracker /usr/local/bin/automated-tor-tracker
ENTRYPOINT ["/usr/local/bin/automated-tor-tracker"]
