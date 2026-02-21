# SPDX-License-Identifier: AGPL-3.0-or-later
# System Operating Theatre - Wolfi-based container
#
# Build: nerdctl build -t sor:latest .
# Run:   nerdctl run --rm -it sor:latest help

# Stage 1: Build
FROM cgr.dev/chainguard/wolfi-base:latest AS builder

# Install build dependencies
RUN apk add --no-cache \
    ldc \
    dub \
    gcc \
    glibc-dev

WORKDIR /build
COPY dub.json .
COPY src/ src/

# Build static binary for portability
RUN dub build --build=release

# Stage 2: Runtime
FROM cgr.dev/chainguard/wolfi-base:latest

# Install runtime dependencies (D runtime)
RUN apk add --no-cache ldc-runtime

WORKDIR /app
COPY --from=builder /build/sor /app/sor

# Non-root user
USER nonroot:nonroot

ENTRYPOINT ["/app/sor"]
CMD ["help"]
