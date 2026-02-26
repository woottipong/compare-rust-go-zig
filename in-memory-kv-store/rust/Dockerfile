FROM rust:1.85-bookworm AS builder
WORKDIR /src
# 1) dependency cache layer
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo 'fn main(){}' > src/main.rs \
    && cargo build --release \
    && rm src/main.rs
# 2) build real binary
COPY src ./src
RUN touch src/main.rs \
    && cargo build --release \
    && strip target/release/in-memory-kv-store

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/target/release/in-memory-kv-store /usr/local/bin/in-memory-kv-store
ENTRYPOINT ["/usr/local/bin/in-memory-kv-store"]
