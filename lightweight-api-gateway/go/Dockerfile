FROM golang:1.23-bookworm AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/gateway-go .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /out/gateway-go /usr/local/bin/gateway-go
EXPOSE 8080
ENTRYPOINT ["gateway-go"]
CMD ["0.0.0.0:8080", "http://backend:3000"]
