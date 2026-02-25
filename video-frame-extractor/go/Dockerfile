FROM golang:1.25-alpine AS builder

RUN apk add --no-cache \
    pkgconfig \
    ffmpeg-dev \
    gcc \
    musl-dev

RUN mkdir -p /out
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=1 go build -o /out/extractor-go .

FROM alpine:3.21
RUN apk add --no-cache ffmpeg-libs

COPY --from=builder /out/extractor-go /usr/local/bin/extractor-go
ENTRYPOINT ["extractor-go"]
