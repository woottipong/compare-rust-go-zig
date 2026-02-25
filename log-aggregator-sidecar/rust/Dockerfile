FROM rust:1.85-bookworm AS builder
WORKDIR /src

# Cache dependencies
COPY Cargo.toml ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release && rm -rf src

# Build actual binary
COPY . .
RUN cargo build --release && strip target/release/log-aggregator-sidecar

FROM debian:bookworm-slim
COPY --from=builder /src/target/release/log-aggregator-sidecar /usr/local/bin/log-aggregator
ENTRYPOINT ["log-aggregator"]
