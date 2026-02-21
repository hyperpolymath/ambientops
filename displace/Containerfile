# syntax=docker/dockerfile:1

# --- Build Stage ---
FROM cgr.dev/chainguard/rust AS builder

WORKDIR /app

# Copy only the necessary files for building
COPY Cargo.toml Cargo.lock ./
COPY src ./src

# Build the release binary
# Using --target x86_64-unknown-linux-musl for a static build compatible with minimal base images
# However, Chainguard rust image might already produce musl-linked binaries.
# Let's try without explicit target first, assuming Chainguard's Rust environment is set up for minimal images.
RUN cargo build --release

# --- Runtime Stage ---
FROM cgr.dev/chainguard/static

# Set the working directory
WORKDIR /usr/local/bin

# Copy the built binary from the build stage
COPY --from=builder /app/target/release/displace .

# Ensure the binary is executable
RUN chmod +x displace

# Define the entrypoint for the container
ENTRYPOINT ["/usr/local/bin/displace"]
