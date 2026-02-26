FROM rust:1.85-bookworm AS builder
WORKDIR /src
COPY Cargo.toml Cargo.lock* ./
RUN mkdir -p src && echo 'fn main(){}' > src/main.rs \
    && cargo build --release \
    && rm src/main.rs

COPY src ./src
RUN touch src/main.rs \
    && cargo build --release \
    && strip target/release/dns-resolver

FROM debian:bookworm-slim
COPY --from=builder /src/target/release/dns-resolver /usr/local/bin/dns-resolver
ENTRYPOINT ["/usr/local/bin/dns-resolver"]
