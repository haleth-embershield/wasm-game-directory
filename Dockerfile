FROM ubuntu:22.04

# Avoid interactive dialogs during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set up environment variables
ENV ZIG_VERSION=0.14.0

# Install essential tools and dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    python3 \
    python3-pip \
    cmake \
    ninja-build \
    ca-certificates \
    wget \
    xz-utils \
    unzip \
    nginx \
    cron \
    jq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js and npm for Emscripten and Bun
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm@latest

# Install Zig
RUN wget https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz \
    && tar -xf zig-linux-x86_64-${ZIG_VERSION}.tar.xz \
    && mv zig-linux-x86_64-${ZIG_VERSION} /usr/local/zig \
    && rm zig-linux-x86_64-${ZIG_VERSION}.tar.xz

# Add Zig to PATH
ENV PATH="/usr/local/zig:${PATH}"

# Install system dependencies that might be needed by Emscripten
# These will be available to Emscripten when it's installed by build.zig
RUN apt-get update && apt-get install -y \
    llvm \
    clang \
    lld \
    libedit-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Enable WebAssembly bulk memory operations
RUN echo "EMSCRIPTEN_FEATURES=['-mbulk-memory']" >> /opt/emsdk/upstream/emscripten/em_config.py

# Set environment variables to support bulk memory operations in wasm
ENV CFLAGS="-mbulk-memory"
ENV LDFLAGS="-mbulk-memory"

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Create necessary directories for our game system
RUN mkdir -p /games /hashes /config /scripts

# Copy configuration files
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY web/ /usr/share/nginx/html/
COPY games.json /config/games.json
COPY scripts/ /scripts/

# Make scripts executable
RUN chmod +x /scripts/*.sh

# Expose port for Nginx
EXPOSE 80

# The entrypoint will be handled by your scripts
ENTRYPOINT ["/scripts/entrypoint.sh"]