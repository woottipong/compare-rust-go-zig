FROM rust:1.85-bookworm AS builder
WORKDIR /src

# Build actual binary
COPY . .
RUN cargo build --release && strip target/release/local-asr-llm-proxy

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libssl3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/target/release/local-asr-llm-proxy /usr/local/bin/asr-proxy
ENTRYPOINT ["asr-proxy"]
CMD ["0.0.0.0:8080", "http://localhost:3000"]
