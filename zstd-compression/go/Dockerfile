FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/zstd-compression .

FROM debian:bookworm-slim
COPY --from=builder /out/zstd-compression /usr/local/bin/zstd-compression
ENTRYPOINT ["/usr/local/bin/zstd-compression"]
