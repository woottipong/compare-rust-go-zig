# Stage 1: Builder
FROM golang:1.25-bookworm AS builder

WORKDIR /app
COPY go.mod main.go ./

RUN mkdir -p /out && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/clm-go .

# Stage 2: Runtime
FROM debian:bookworm-slim

COPY --from=builder /out/clm-go /usr/local/bin/clm-go

ENTRYPOINT ["clm-go"]
