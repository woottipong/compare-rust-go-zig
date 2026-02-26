FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends wget xz-utils ca-certificates \
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
RUN mkdir -p /out && cp zig-out/bin/png-encoder /out/png-encoder

FROM debian:bookworm-slim
COPY --from=builder /out/png-encoder /usr/local/bin/png-encoder
ENTRYPOINT ["/usr/local/bin/png-encoder"]
