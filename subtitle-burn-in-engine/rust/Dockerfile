FROM rust:1.83-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libavformat-dev \
    libavcodec-dev \
    libavutil-dev \
    libswscale-dev \
    libswresample-dev \
    clang \
    llvm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main(){}" > src/main.rs
RUN cargo build --release
RUN rm -rf src

COPY src ./src
RUN touch src/main.rs && cargo build --release
RUN cp target/release/subtitle-burn-in-engine /out/subtitle-rust 2>/dev/null || \
    cp target/release/$(ls target/release/ | grep -v '\.' | head -1) /out/subtitle-rust

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libavformat60 libavcodec60 libavutil58 libswscale7 libswresample4 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/subtitle-rust /usr/local/bin/subtitle-rust
ENTRYPOINT ["subtitle-rust"]
