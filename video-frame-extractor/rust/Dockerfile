FROM rust:1.83-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libavformat-dev libavcodec-dev libavutil-dev \
    libswscale-dev libavfilter-dev libavdevice-dev \
    clang llvm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo 'fn main(){}' > src/main.rs \
    && cargo build --release \
    && rm -rf src

COPY src ./src
RUN touch src/main.rs \
    && cargo build --release \
    && strip target/release/video-frame-extractor

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libavformat59 libavcodec59 libavutil57 libswscale6 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/target/release/video-frame-extractor /usr/local/bin/extractor-rust
ENTRYPOINT ["extractor-rust"]
