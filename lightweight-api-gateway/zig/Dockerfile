FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q https://ziglang.org/download/0.15.0/zig-linux-x86_64-0.15.0.tar.xz \
    && tar -xf zig-linux-x86_64-0.15.0.tar.xz \
    && mv zig-linux-x86_64-0.15.0 /usr/local/zig \
    && rm zig-linux-x86_64-0.15.0.tar.xz
ENV PATH="/usr/local/zig:$PATH"

WORKDIR /src
COPY build.zig build.zig.zon ./
COPY src ./src

# Fetch Zap dependency (needs network during build)
RUN zig fetch --save "git+https://github.com/zigzap/zap#v0.11.0" 2>/dev/null || true
RUN zig build -Doptimize=ReleaseFast

# Zap builds facil.io as a shared lib — copy alongside binary
RUN cp zig-out/bin/lightweight-api-gateway /out/gateway-zig && \
    find .zig-cache -name "libfacil.io.so*" -exec cp {} /out/ \; 2>/dev/null || \
    find .zig-cache -name "*.so*" -exec cp {} /out/ \; 2>/dev/null || true

FROM debian:bookworm-slim
COPY --from=builder /out/gateway-zig /usr/local/bin/gateway-zig
COPY --from=builder /out/ /usr/local/lib/facil/
RUN ldconfig /usr/local/lib/facil 2>/dev/null || true
EXPOSE 8080
ENTRYPOINT ["gateway-zig"]
