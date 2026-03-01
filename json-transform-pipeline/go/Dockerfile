FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/json-transform-pipeline .

FROM debian:bookworm-slim
COPY --from=builder /out/json-transform-pipeline /usr/local/bin/json-transform-pipeline
ENTRYPOINT ["/usr/local/bin/json-transform-pipeline"]
