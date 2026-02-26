FROM rust:1.85-bookworm AS builder
WORKDIR /src
COPY Cargo.toml Cargo.lock* ./
RUN mkdir -p src && echo 'fn main(){}' > src/main.rs && cargo build --release && rm src/main.rs
COPY src ./src
RUN touch src/main.rs && cargo build --release && strip target/release/web-accessibility-crawler

FROM debian:bookworm-slim
COPY --from=builder /src/target/release/web-accessibility-crawler /usr/local/bin/web-accessibility-crawler
ENTRYPOINT ["/usr/local/bin/web-accessibility-crawler"]
