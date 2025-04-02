FROM ubuntu:22.04

# Avoid interactive dialogs during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set up environment variables
ENV ZIG_VERSION=0.14.0
ENV EMSDK_VERSION=3.1.48

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

# Install Emscripten
WORKDIR /opt
RUN git clone https://github.com/emscripten-core/emsdk.git \
    && cd emsdk \
    && ./emsdk install ${EMSDK_VERSION} \
    && ./emsdk activate ${EMSDK_VERSION}

# Add Emscripten to PATH
ENV PATH="/opt/emsdk:/opt/emsdk/upstream/emscripten:/opt/emsdk/node/current/bin:/opt/emsdk/upstream/bin:${PATH}"
ENV EMSDK="/opt/emsdk"
ENV EM_CONFIG="/opt/emsdk/.emscripten"

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