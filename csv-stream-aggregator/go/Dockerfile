FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/csv-stream-aggregator .

FROM debian:bookworm-slim
COPY --from=builder /out/csv-stream-aggregator /usr/local/bin/csv-stream-aggregator
ENTRYPOINT ["/usr/local/bin/csv-stream-aggregator"]
