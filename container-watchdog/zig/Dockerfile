FROM debian:bookworm-slim AS builder
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends wget ca-certificates xz-utils && rm -rf /var/lib/apt/lists/*
RUN ZIG_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && wget -q https://ziglang.org/download/0.15.2/zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && tar -xf zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && mv zig-${ZIG_ARCH}-linux-0.15.2 /usr/local/zig
WORKDIR /src
COPY . .
RUN /usr/local/zig/zig build -Doptimize=ReleaseFast && mkdir -p /out && cp zig-out/bin/container-watchdog /out/

FROM debian:bookworm-slim
COPY --from=builder /out/container-watchdog /usr/local/bin/container-watchdog
ENTRYPOINT ["/usr/local/bin/container-watchdog"]
