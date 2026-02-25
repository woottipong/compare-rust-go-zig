FROM golang:1.25-bookworm AS builder
WORKDIR /src

# Cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Build actual binary
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/log-aggregator .

FROM debian:bookworm-slim
COPY --from=builder /out/log-aggregator /usr/local/bin/log-aggregator
ENTRYPOINT ["log-aggregator"]
