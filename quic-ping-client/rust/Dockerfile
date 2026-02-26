FROM rust:1.85-bookworm AS builder
WORKDIR /src
COPY Cargo.toml Cargo.lock* ./
RUN mkdir -p src && echo 'fn main(){}' > src/main.rs && cargo build --release && rm src/main.rs
COPY src ./src
RUN touch src/main.rs && cargo build --release && strip target/release/quic-ping-client

FROM debian:bookworm-slim
COPY --from=builder /src/target/release/quic-ping-client /usr/local/bin/quic-ping-client
ENTRYPOINT ["/usr/local/bin/quic-ping-client"]
