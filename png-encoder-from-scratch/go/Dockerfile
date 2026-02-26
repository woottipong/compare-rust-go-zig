FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/png-encoder .

FROM debian:bookworm-slim
COPY --from=builder /out/png-encoder /usr/local/bin/png-encoder
ENTRYPOINT ["/usr/local/bin/png-encoder"]
