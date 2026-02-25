FROM rust:1.83-bookworm AS builder

WORKDIR /src
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo 'fn main(){}' > src/main.rs \
    && cargo build --release \
    && rm -rf src

COPY src ./src
RUN touch src/main.rs \
    && cargo build --release \
    && strip target/release/lightweight-api-gateway

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/target/release/lightweight-api-gateway /usr/local/bin/gateway-rust
EXPOSE 8080
ENTRYPOINT ["gateway-rust"]
CMD ["0.0.0.0:8080", "http://backend:3000"]
