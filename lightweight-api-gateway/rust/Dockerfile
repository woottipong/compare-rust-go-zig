FROM rust:1.83-bookworm AS builder

WORKDIR /src
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main(){}" > src/main.rs
RUN cargo build --release
RUN rm -rf src

COPY src ./src
RUN touch src/main.rs && cargo build --release
RUN cp target/release/lightweight-api-gateway /out/gateway-rust

FROM debian:bookworm-slim
COPY --from=builder /out/gateway-rust /usr/local/bin/gateway-rust
EXPOSE 8080
ENTRYPOINT ["gateway-rust"]
