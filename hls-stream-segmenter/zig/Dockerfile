FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget xz-utils \
    pkg-config \
    libavformat-dev \
    libavcodec-dev \
    libavutil-dev \
    libswscale-dev \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q https://ziglang.org/download/0.15.0/zig-linux-x86_64-0.15.0.tar.xz \
    && tar -xf zig-linux-x86_64-0.15.0.tar.xz \
    && mv zig-linux-x86_64-0.15.0 /usr/local/zig \
    && rm zig-linux-x86_64-0.15.0.tar.xz
ENV PATH="/usr/local/zig:$PATH"

WORKDIR /src
COPY build.zig build.zig.zon* ./
COPY src ./src
RUN zig build -Doptimize=ReleaseFast
RUN cp zig-out/bin/hls-stream-segmenter /out/segmenter-zig

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libavformat60 libavcodec60 libavutil58 libswscale7 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/segmenter-zig /usr/local/bin/segmenter-zig
ENTRYPOINT ["segmenter-zig"]
