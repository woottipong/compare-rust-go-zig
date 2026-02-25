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
RUN CGO_ENABLED=1 go build -o /out/segmenter-go .

FROM alpine:3.21
RUN apk add --no-cache ffmpeg-libs

COPY --from=builder /out/segmenter-go /usr/local/bin/segmenter-go
ENTRYPOINT ["segmenter-go"]
