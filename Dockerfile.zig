# Multi-stage Dockerfile for Zig-only clustering component
# Optimized for minimal runtime size and fast startup

# Build stage - includes Zig compiler and build dependencies
FROM alpine:3.19 AS zig-builder

# Install build dependencies
RUN apk add --no-cache \
    wget \
    xz \
    sqlite-dev \
    musl-dev \
    gcc \
    && rm -rf /var/cache/apk/*

# Install Zig compiler
ARG ZIG_VERSION=0.13.0
RUN wget -q https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz \
    && tar -xf zig-linux-x86_64-${ZIG_VERSION}.tar.xz \
    && mv zig-linux-x86_64-${ZIG_VERSION} /usr/local/zig \
    && ln -s /usr/local/zig/zig /usr/local/bin/zig \
    && rm zig-linux-x86_64-${ZIG_VERSION}.tar.xz

# Set up workspace
WORKDIR /build

# Copy Zig clustering source
COPY poker_ai/zig_clustering/ ./

# Build optimized release binary
RUN zig build -Doptimize=ReleaseFast --prefix-exe-dir /build/bin

# Runtime stage - minimal Alpine with only runtime dependencies
FROM alpine:3.19 AS runtime

# Install only runtime dependencies
RUN apk add --no-cache \
    sqlite \
    && rm -rf /var/cache/apk/*

# Create non-root user for security
RUN addgroup -g 1000 poker && \
    adduser -D -s /bin/sh -u 1000 -G poker poker

# Copy binary from build stage
COPY --from=zig-builder /build/bin/poker_clustering /usr/local/bin/
RUN chmod +x /usr/local/bin/poker_clustering

# Create data directory
RUN mkdir -p /data && chown poker:poker /data

# Switch to non-root user
USER poker
WORKDIR /data

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD poker_clustering --help || exit 1

# Default command
CMD ["poker_clustering", "--help"]

# Labels for metadata
LABEL org.opencontainers.image.title="Poker AI Zig Clustering"
LABEL org.opencontainers.image.description="High-performance poker hand clustering component written in Zig"
LABEL org.opencontainers.image.vendor="Poker AI"
LABEL org.opencontainers.image.licenses="GPL-3.0"
LABEL org.opencontainers.image.source="https://github.com/fedden/poker_ai"