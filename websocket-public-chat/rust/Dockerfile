FROM rust:1.85-bookworm AS builder
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src && echo 'fn main(){}' > src/main.rs \
    && cargo build --release \
    && rm src/main.rs
COPY src ./src
RUN touch src/main.rs \
    && cargo build --release \
    && strip target/release/websocket-public-chat

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/target/release/websocket-public-chat /usr/local/bin/websocket-public-chat
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/websocket-public-chat"]
