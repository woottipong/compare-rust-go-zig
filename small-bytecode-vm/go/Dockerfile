FROM golang:1.25-bookworm AS builder
WORKDIR /src
COPY . .
RUN mkdir -p /out && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/small-bytecode-vm .

FROM debian:bookworm-slim
COPY --from=builder /out/small-bytecode-vm /usr/local/bin/small-bytecode-vm
ENTRYPOINT ["/usr/local/bin/small-bytecode-vm"]
