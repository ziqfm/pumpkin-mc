# syntax=docker/dockerfile:1
ARG RUST_VERSION=1
ARG DEBIAN_VERSION=bookworm

# Import xx for cross-compilation
FROM --platform=$BUILDPLATFORM docker.io/tonistiigi/xx AS xx
FROM --platform=$BUILDPLATFORM rust:${RUST_VERSION}-slim-${DEBIAN_VERSION} AS builder

# Inject xx scripts into the builder
COPY --from=xx / /
ARG TARGETPLATFORM

# Install host build dependencies
RUN apt-get update && apt-get install -y \
    clang lld curl jq pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install lddtree to extract dynamic libraries later
RUN curl --retry 5 -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash \
    && cargo binstall --no-confirm lddtree@0.5.0

# Install target architecture C libraries (arm64 libc)
RUN xx-apt-get install -y libc6-dev

WORKDIR /app
COPY . .

# Setup Rust cross-compilation environment via xx
RUN xx-cargo --setup-target-triple

# Enable Clang, LTO, and Pi 5 (Cortex-A76) hardware optimizations
ARG TARGET_CPU=cortex-a76
ENV CC=clang CXX=clang++
ENV RUSTFLAGS="-Clinker-plugin-lto -Clink-arg=-fuse-ld=lld -C target-cpu=${TARGET_CPU}"

# Compile Pumpkin specifically for the target architecture
RUN xx-cargo build --release --locked

# Isolate the binary and dynamically linked libraries
RUN <<'EOF'
    set -e
    mkdir -p /out/sbin /out/libs /out/libs-root
    
    # Locate the compiled binary using Cargo metadata and xx's triple
    TARGET_DIR=$(cargo metadata --no-deps --format-version 1 | jq -r ".target_directory")
    TRIPLE=$(xx-cargo --print-target-triple)
    cp "$TARGET_DIR/$TRIPLE/release/pumpkin" /out/sbin/pumpkin

    # Use lddtree to recursively copy ALL required dynamic libraries (libc, libgcc, etc.)
    lddtree /out/sbin/pumpkin | awk '{print $(NF-0) " " $1}' | sort -u -k 1,1 | \
        awk '{dest = ($2 ~ /^\//) ? "/out/libs-root" $2 : "/out/libs/" $2; print "install -D " $1 " " dest}' | \
        while read cmd; do eval "$cmd"; done
EOF

# ---------------------------------------------------------
# Final Stage: The Blank Canvas
# ---------------------------------------------------------
FROM scratch

# Copy root certificates (needed if Pumpkin makes outward HTTPS calls)
COPY --from=builder /etc/ssl/certs /etc/ssl/certs

# Copy the extracted dynamic libraries into the exact paths they expect
COPY --from=builder /out/libs-root/ /
COPY --from=builder /out/libs/ /usr/lib/

# Copy the compiled, optimized Pumpkin binary
COPY --from=builder /out/sbin/ /sbin/

# Configure the environment
ENV LD_LIBRARY_PATH=/usr/lib
ENV RUST_BACKTRACE=1

# Minecraft port
EXPOSE 25565

# Set a working directory so server files (world, properties) 
# don't clutter the root directory when bound to a volume
WORKDIR /server
USER 1000:1000

CMD ["/sbin/pumpkin"]
