FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/websocket-public-chat .

FROM debian:bookworm-slim
COPY --from=builder /out/websocket-public-chat /usr/local/bin/websocket-public-chat
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/websocket-public-chat"]
