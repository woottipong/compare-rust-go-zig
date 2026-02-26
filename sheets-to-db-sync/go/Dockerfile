FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/sheets-to-db-sync .

FROM debian:bookworm-slim
COPY --from=builder /out/sheets-to-db-sync /usr/local/bin/sheets-to-db-sync
ENTRYPOINT ["/usr/local/bin/sheets-to-db-sync"]
