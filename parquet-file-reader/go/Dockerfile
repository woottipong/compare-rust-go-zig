FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/parquet-file-reader .

FROM debian:bookworm-slim
COPY --from=builder /out/parquet-file-reader /usr/local/bin/parquet-file-reader
ENTRYPOINT ["/usr/local/bin/parquet-file-reader"]
