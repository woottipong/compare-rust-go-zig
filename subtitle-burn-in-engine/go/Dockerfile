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
RUN CGO_ENABLED=1 go build -o /out/subtitle-go .

FROM alpine:3.21
RUN apk add --no-cache ffmpeg-libs

COPY --from=builder /out/subtitle-go /usr/local/bin/subtitle-go
ENTRYPOINT ["subtitle-go"]
