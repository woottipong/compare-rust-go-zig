FROM debian:bookworm-slim AS builder
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN ZIG_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && wget -q https://ziglang.org/download/0.15.2/zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && tar -xf zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && mv zig-${ZIG_ARCH}-linux-0.15.2 /usr/local/zig \
    && rm zig-${ZIG_ARCH}-linux-0.15.2.tar.xz
ENV PATH="/usr/local/zig:$PATH"
WORKDIR /src
COPY build.zig build.zig.zon ./
COPY src ./src
RUN mkdir -p /out && zig build -Doptimize=ReleaseFast && cp zig-out/bin/json-transform-pipeline /out/json-transform-pipeline

FROM debian:bookworm-slim
COPY --from=builder /out/json-transform-pipeline /usr/local/bin/json-transform-pipeline
ENTRYPOINT ["/usr/local/bin/json-transform-pipeline"]
