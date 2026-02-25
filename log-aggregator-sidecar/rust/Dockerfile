FROM rust:1.85-bookworm AS builder
WORKDIR /src

# Cache dependency layer: copy manifests only, build deps with dummy main
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo 'fn main(){}' > src/main.rs \
    && cargo build --release \
    && rm src/main.rs

# Build real binary
COPY src ./src
RUN touch src/main.rs \
    && cargo build --release \
    && strip target/release/log-aggregator-sidecar

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/target/release/log-aggregator-sidecar /usr/local/bin/log-aggregator
ENTRYPOINT ["/usr/local/bin/log-aggregator"]
