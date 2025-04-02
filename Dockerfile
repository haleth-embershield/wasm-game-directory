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
EXPOSE 8081

# Entry script to start services
ENTRYPOINT ["/scripts/entrypoint.sh"]
