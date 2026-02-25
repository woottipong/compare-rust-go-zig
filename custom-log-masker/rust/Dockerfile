# Stage 1: Builder
FROM rust:1.83-bookworm AS builder

WORKDIR /app

# Cache dependencies
COPY Cargo.toml ./
RUN mkdir -p src && echo 'fn main() {}' > src/main.rs
RUN cargo build --release && rm -rf src

# Build actual source
COPY src ./src
RUN cargo build --release && \
    strip target/release/custom-log-masker && \
    mkdir -p /out && \
    cp target/release/custom-log-masker /out/clm-rust

# Stage 2: Runtime
FROM debian:bookworm-slim

COPY --from=builder /out/clm-rust /usr/local/bin/clm-rust

ENTRYPOINT ["clm-rust"]
