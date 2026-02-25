# Stage 1: builder
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y wget xz-utils ca-certificates && rm -rf /var/lib/apt/lists/*

# Install Zig 0.15.2
ARG TARGETARCH
RUN ZIG_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && wget -q https://ziglang.org/download/0.15.2/zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && tar -xf zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && mv zig-${ZIG_ARCH}-linux-0.15.2 /usr/local/zig \
    && rm zig-${ZIG_ARCH}-linux-0.15.2.tar.xz

ENV PATH="/usr/local/zig:${PATH}"

WORKDIR /app
COPY build.zig ./
COPY src ./src

# Build
RUN zig build -Doptimize=ReleaseFast
RUN mkdir -p /out && cp zig-out/bin/realtime-audio-chunker /out/realtime-audio-chunker-zig

# Stage 2: runtime
FROM debian:bookworm-slim
COPY --from=builder /out/realtime-audio-chunker-zig /usr/local/bin/realtime-audio-chunker-zig

ENTRYPOINT ["realtime-audio-chunker-zig"]
