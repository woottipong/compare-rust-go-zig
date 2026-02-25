# Stage 1: builder
FROM debian:bookworm-slim AS builder

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    xz-utils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download and install Zig
ARG TARGETARCH
RUN ZIG_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && wget -q https://ziglang.org/download/0.15.2/zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && tar -xf zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && mv zig-${ZIG_ARCH}-linux-0.15.2 /usr/local/zig \
    && rm zig-${ZIG_ARCH}-linux-0.15.2.tar.xz

ENV PATH="/usr/local/zig:$PATH"

WORKDIR /build

# Copy all source files
COPY build.zig ./
COPY src/ ./src/

# Build
RUN zig build -Doptimize=ReleaseFast

# Stage 2: runtime
FROM debian:bookworm-slim

WORKDIR /app

# Copy the built binary
COPY --from=builder /build/zig-out/bin/vdi-zig /usr/local/bin/vdi-zig

ENTRYPOINT ["vdi-zig"]
