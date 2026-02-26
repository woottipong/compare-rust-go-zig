FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends wget xz-utils ca-certificates libc6-dev \
    && rm -rf /var/lib/apt/lists/*

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

RUN zig build -Doptimize=ReleaseFast
RUN mkdir -p /out && cp zig-out/bin/dns-resolver /out/dns-resolver

FROM debian:bookworm-slim
COPY --from=builder /out/dns-resolver /usr/local/bin/dns-resolver
ENTRYPOINT ["/usr/local/bin/dns-resolver"]
