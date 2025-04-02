# Single-stage build with Zig and Nginx
FROM nginx:alpine

# Install required tools
RUN apk add --no-cache \
    bash \
    git \
    curl \
    jq \
    xz \
    busybox-suid \
    wget \
    nodejs \
    npm \
    unzip \
    # Emscripten dependencies
    python3 \
    cmake \
    llvm \
    clang \
    lld \
    # Dependencies for Puppeteer with GPU support
    chromium \
    mesa-dri-gallium \
    mesa-gl \
    mesa-egl \
    mesa-gles \
    mesa-vulkan-intel \
    mesa-vulkan-layers \
    ttf-freefont \
    pango \
    libstdc++ \
    harfbuzz \
    nss \
    freetype \
    freetype-dev \
    dbus \
    fontconfig \
    xvfb \
    eudev

# Set Puppeteer environment variables
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    DISPLAY=:99

# Install Zig (latest version)
RUN curl -L https://ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz | tar -xJ -C /usr/local
ENV PATH="/usr/local/zig-linux-x86_64-0.14.0:${PATH}"

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Install Emscripten
RUN git clone https://github.com/emscripten-core/emsdk.git /opt/emsdk \
    && cd /opt/emsdk \
    && ./emsdk install 3.1.45 \
    && ./emsdk activate 3.1.45 \
    && . /opt/emsdk/emsdk_env.sh \
    # Verify installation paths exist
    && ls -la /opt/emsdk/upstream/bin/ \
    && ls -la /opt/emsdk/node/ \
    # Create symlinks if needed
    && mkdir -p /opt/emsdk/upstream/bin \
    && ln -sf /usr/bin/clang /opt/emsdk/upstream/bin/clang \
    && ln -sf /usr/bin/llvm-ar /opt/emsdk/upstream/bin/llvm-ar \
    && mkdir -p /opt/emsdk/node/20.18.0_64bit/bin/ \
    && ln -sf /usr/bin/node /opt/emsdk/node/20.18.0_64bit/bin/node

# Set environment variables for Emscripten
ENV PATH="/opt/emsdk:/opt/emsdk/upstream/emscripten:/opt/emsdk/node/20.18.0_64bit/bin:/opt/emsdk/upstream/bin:${PATH}"
ENV EMSDK="/opt/emsdk"
ENV EM_CONFIG="/opt/emsdk/.emscripten"
# Verify emcc can run
RUN emcc --version

# Create necessary directories
RUN mkdir -p /games /hashes /config /scripts

# Copy configuration files
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY web/ /usr/share/nginx/html/
COPY games.json /config/games.json
COPY scripts/ /scripts/

# Make scripts executable
RUN chmod +x /scripts/*.sh

# Expose port
EXPOSE 80

# Entry script to start services
ENTRYPOINT ["/scripts/entrypoint.sh"]
