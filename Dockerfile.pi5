# ---------------------------------------------------------
# Stage 1: Native ARM64 Builder
# ---------------------------------------------------------
FROM rust:1-slim-trixie AS builder

# Install build dependencies required by standard Rust/C compilation
RUN apt-get update && apt-get install -y \
    clang lld pkg-config git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

# Force maximum performance profile overrides for a tiny, fast binary
ENV CARGO_PROFILE_RELEASE_LTO="fat"
ENV CARGO_PROFILE_RELEASE_STRIP="symbols"
ENV CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1

# Enable Pi 5 (Cortex-A76) hardware optimizations and fast linker
ENV CC=clang CXX=clang++
ENV RUSTFLAGS="-Clinker-plugin-lto -Clink-arg=-fuse-ld=lld -C target-cpu=cortex-a76"

# Build the binary natively on ARM64
RUN cargo build --release --locked

# ---------------------------------------------------------
# Stage 2: Minimal Trixie Runtime
# ---------------------------------------------------------
FROM debian:trixie-slim

# Install root certificates (required for outward HTTPS calls)
# and clean up the apt cache to keep the image extremely small
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for security
RUN useradd -m -u 1000 -U -s /bin/sh pumpkin

WORKDIR /server

# Copy only the compiled binary from the builder
COPY --from=builder --chown=pumpkin:pumpkin /app/target/release/pumpkin /usr/local/bin/pumpkin

# Configure the environment
ENV RUST_BACKTRACE=1
EXPOSE 25565

# Run as the unprivileged user
USER pumpkin
CMD ["pumpkin"]
