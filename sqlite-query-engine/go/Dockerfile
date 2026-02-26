FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/sqlite-query-engine .

FROM debian:bookworm-slim
COPY --from=builder /out/sqlite-query-engine /usr/local/bin/sqlite-query-engine
ENTRYPOINT ["/usr/local/bin/sqlite-query-engine"]
