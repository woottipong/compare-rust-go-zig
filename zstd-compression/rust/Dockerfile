FROM rust:1.85-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    libzstd-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo 'fn main(){}' > src/main.rs \
    && cargo build --release \
    && rm src/main.rs
COPY src ./src
RUN touch src/main.rs \
    && cargo build --release \
    && strip target/release/zstd-compression

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libzstd1 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/target/release/zstd-compression /usr/local/bin/zstd-compression
ENTRYPOINT ["/usr/local/bin/zstd-compression"]
