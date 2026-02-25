FROM rust:1.83-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libavformat-dev libavcodec-dev libavutil-dev \
    libswscale-dev libavfilter-dev libavdevice-dev \
    clang llvm \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /out
WORKDIR /src
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main(){}" > src/main.rs
RUN cargo build --release
RUN rm -rf src

COPY src ./src
RUN touch src/main.rs && cargo build --release
RUN cp target/release/hls-stream-segmenter /out/segmenter-rust

FROM alpine:3.21
RUN apk add --no-cache ffmpeg-libs

COPY --from=builder /out/segmenter-rust /usr/local/bin/segmenter-rust
ENTRYPOINT ["segmenter-rust"]
