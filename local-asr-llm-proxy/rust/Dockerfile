FROM rust:1.85-bookworm AS builder
WORKDIR /src

# Cache dependency layer
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo 'fn main(){}' > src/main.rs \
    && cargo build --release \
    && rm src/main.rs

# Build real binary
COPY src ./src
RUN touch src/main.rs \
    && cargo build --release \
    && strip target/release/local-asr-llm-proxy

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/target/release/local-asr-llm-proxy /usr/local/bin/asr-proxy
ENTRYPOINT ["/usr/local/bin/asr-proxy"]
CMD ["0.0.0.0:8080", "http://localhost:3000"]
