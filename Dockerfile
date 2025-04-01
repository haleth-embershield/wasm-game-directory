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
    # Dependencies for Playwright
    chromium \
    nss \
    freetype \
    freetype-dev \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    dbus \
    fontconfig \
    mesa-gl \
    mesa-egl \
    mesa-gles \
    libstdc++ \
    pango \
    xvfb

# Set SwiftShader and Playwright environment variables
ENV SWIFTSHADER_DISABLE_PERFETTO=1 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=0 \
    PLAYWRIGHT_BROWSERS_PATH=/playwright-browsers \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    DISPLAY=:99

# Install Zig (latest version)
RUN curl -L https://ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz | tar -xJ -C /usr/local
ENV PATH="/usr/local/zig-linux-x86_64-0.14.0:${PATH}"

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Install Playwright in its own directory
RUN mkdir -p /playwright-browsers && \
    mkdir -p /playwright-install && \
    cd /playwright-install && \
    echo '{"name":"playwright-install","version":"1.0.0","private":true}' > package.json && \
    npm install playwright-chromium playwright-core && \
    # Set up chromium with SwiftShader
    mkdir -p /root/.config/chromium-browser && \
    echo '{"use_angle":true,"use_swift_shader":true}' > /root/.config/chromium-browser/Local\ State

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
