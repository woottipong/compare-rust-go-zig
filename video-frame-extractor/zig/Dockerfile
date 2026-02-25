FROM alpine:3.21 AS builder

RUN apk add --no-cache \
    wget xz \
    pkgconfig \
    ffmpeg-dev \
    musl-dev \
    gcc

RUN wget -q https://ziglang.org/download/0.14.0/zig-linux-aarch64-0.14.0.tar.xz \
    && tar -xf zig-linux-aarch64-0.14.0.tar.xz \
    && mv zig-linux-aarch64-0.14.0 /usr/local/zig \
    && rm zig-linux-aarch64-0.14.0.tar.xz
ENV PATH="/usr/local/zig:$PATH"

WORKDIR /src
COPY build.zig build.zig.zon* ./
COPY src ./src
RUN mkdir -p /out && zig build -Doptimize=ReleaseFast
RUN cp zig-out/bin/video-frame-extractor /out/extractor-zig

FROM alpine:3.21
RUN apk add --no-cache ffmpeg-libs

COPY --from=builder /out/extractor-zig /usr/local/bin/extractor-zig
ENTRYPOINT ["extractor-zig"]
