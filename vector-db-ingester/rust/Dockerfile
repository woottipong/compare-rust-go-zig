# Stage 1: builder
FROM rust:1.85-bookworm AS builder

WORKDIR /build

# Copy Cargo files first for caching
COPY Cargo.toml Cargo.lock ./

# Create dummy main.rs for dependency build
RUN mkdir -p src && echo "fn main() {}" > src/main.rs

# Build dependencies
RUN cargo build --release

# Copy real source
COPY src/ ./src/

# Build release
RUN cargo build --release

# Strip binary
RUN strip target/release/vector-db-ingester

# Stage 2: runtime
FROM debian:bookworm-slim

WORKDIR /app

COPY --from=builder /build/target/release/vector-db-ingester /usr/local/bin/vdi-rust

RUN mkdir -p /data

ENTRYPOINT ["vdi-rust"]
CMD ["/data/test.json"]
