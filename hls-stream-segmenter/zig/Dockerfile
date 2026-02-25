FROM debian:bookworm-slim AS builder
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget xz-utils ca-certificates pkg-config \
    libavformat-dev libavcodec-dev libavutil-dev libswscale-dev \
    && rm -rf /var/lib/apt/lists/*

RUN ZIG_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && wget -q https://ziglang.org/download/0.15.2/zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && tar -xf zig-${ZIG_ARCH}-linux-0.15.2.tar.xz \
    && mv zig-${ZIG_ARCH}-linux-0.15.2 /usr/local/zig \
    && rm zig-${ZIG_ARCH}-linux-0.15.2.tar.xz
ENV PATH="/usr/local/zig:$PATH"

WORKDIR /src
COPY build.zig ./
COPY src ./src
RUN mkdir -p /out \
    && zig build -Doptimize=ReleaseFast \
    && cp zig-out/bin/hls-stream-segmenter /out/segmenter-zig

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libavformat59 libavcodec59 libavutil57 libswscale6 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/segmenter-zig /usr/local/bin/segmenter-zig
ENTRYPOINT ["segmenter-zig"]
