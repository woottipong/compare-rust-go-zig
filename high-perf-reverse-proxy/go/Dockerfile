FROM golang:1.23-bookworm AS builder
WORKDIR /app
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/hprp-go .

FROM debian:bookworm-slim
COPY --from=builder /out/hprp-go /usr/local/bin/hprp-go
ENTRYPOINT ["hprp-go"]
