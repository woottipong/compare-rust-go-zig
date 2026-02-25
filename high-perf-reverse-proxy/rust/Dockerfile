FROM rust:1.83-bookworm AS builder
WORKDIR /usr/src/app
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main() {println!(\"if you see this, the build failed\")}" > src/main.rs && cargo build --release && rm -rf src
COPY src ./src
RUN touch src/main.rs && cargo build --release
RUN strip target/release/high-perf-reverse-proxy && mkdir -p /out && cp target/release/high-perf-reverse-proxy /out/hprp-rust

FROM debian:bookworm-slim
COPY --from=builder /out/hprp-rust /usr/local/bin/hprp-rust
ENTRYPOINT ["hprp-rust"]
