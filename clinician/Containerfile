# SPDX-License-Identifier: AGPL-3.0-or-later
# Personal Sysadmin - Containerized with Wolfi for security
#
# Uses Wolfi base for minimal attack surface:
# - No shell by default (added only for debugging builds)
# - musl libc
# - Frequent security updates
# - Designed for containers
#
# Build: nerdctl build -t personal-sysadmin:latest .
# Run:   nerdctl run --rm -it \
#          --security-opt seccomp=./seccomp.json \
#          --cap-drop=ALL \
#          --read-only \
#          -v /proc:/host/proc:ro \
#          -v /sys:/host/sys:ro \
#          -v ~/.local/share/psa:/data \
#          -v /run/user/$UID/psa.sock:/run/psa.sock \
#          personal-sysadmin:latest

# Stage 1: Build
FROM cgr.dev/chainguard/wolfi-base:latest AS builder

# Install Rust toolchain
RUN apk add --no-cache rust cargo build-base openssl-dev

WORKDIR /build
COPY Cargo.toml Cargo.lock ./
COPY src ./src

# Build release binary
RUN cargo build --release --locked

# Stage 2: Runtime (minimal)
FROM cgr.dev/chainguard/wolfi-base:latest AS runtime

# Security labels
LABEL org.opencontainers.image.title="Personal Sysadmin"
LABEL org.opencontainers.image.description="AI-assisted Linux system administration toolkit"
LABEL org.opencontainers.image.source="https://github.com/hyperpolymath/personal-sysadmin"
LABEL org.opencontainers.image.licenses="AGPL-3.0-or-later"
LABEL org.opencontainers.image.vendor="hyperpolymath"

# Install minimal runtime dependencies
RUN apk add --no-cache \
    libgcc \
    ca-certificates \
    && rm -rf /var/cache/apk/*

# Create non-root user
RUN adduser -D -u 1000 psa
USER psa

# Copy binary from builder
COPY --from=builder /build/target/release/psa /usr/local/bin/psa

# Create data directories
RUN mkdir -p /home/psa/.local/share/psa/rules \
    && mkdir -p /home/psa/.cache/psa \
    && mkdir -p /home/psa/.config/psa

# Set environment
ENV PSA_DATA_DIR=/home/psa/.local/share/psa
ENV PSA_CACHE_DIR=/home/psa/.cache/psa
ENV PSA_CONFIG_DIR=/home/psa/.config/psa
ENV RUST_LOG=info

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/psa", "health"]

# Default to daemon mode
ENTRYPOINT ["/usr/local/bin/psa"]
CMD ["daemon"]
