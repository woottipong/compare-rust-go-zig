# Stage 1: builder
FROM rust:1.83-bookworm AS builder

WORKDIR /usr/src/app
COPY Cargo.toml Cargo.lock* ./

# Create a dummy main to cache dependencies
RUN mkdir src && \
    echo "fn main() {println!(\"if you see this, the build failed\")}" > src/main.rs && \
    cargo build --release && \
    rm -rf src

# Copy real source code
COPY src ./src

# Build real binary
RUN touch src/main.rs && cargo build --release

# Strip binary to reduce size
RUN strip target/release/realtime-audio-chunker && \
    mkdir -p /out && \
    cp target/release/realtime-audio-chunker /out/realtime-audio-chunker-rust

# Stage 2: runtime
FROM debian:bookworm-slim
COPY --from=builder /out/realtime-audio-chunker-rust /usr/local/bin/realtime-audio-chunker-rust

ENTRYPOINT ["realtime-audio-chunker-rust"]
