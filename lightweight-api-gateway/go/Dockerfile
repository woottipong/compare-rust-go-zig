FROM golang:1.23-bookworm AS builder

WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN go build -o /out/gateway-go .

FROM debian:bookworm-slim
COPY --from=builder /out/gateway-go /usr/local/bin/gateway-go
EXPOSE 8080
ENTRYPOINT ["gateway-go"]
