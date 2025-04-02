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
    # chromium \
    # mesa-dri-gallium \
    # mesa-gl \
    # mesa-egl \
    # mesa-gles \
    # mesa-vulkan-intel \
    # mesa-vulkan-layers \
    # ttf-freefont \
    # pango \
    # libstdc++ \
    # harfbuzz \
    # nss \
    # freetype \
    # freetype-dev \
    # dbus \
    # fontconfig \
    # xvfb \
    # eudev

# Set Puppeteer environment variables
# ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
#     PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser \
#     DISPLAY=:99

# Install Zig (latest version)
RUN curl -L https://ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz | tar -xJ -C /usr/local
ENV PATH="/usr/local/zig-linux-x86_64-0.14.0:${PATH}"

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Install Emscripten
RUN git clone https://github.com/emscripten-core/emsdk.git /opt/emsdk \
    && cd /opt/emsdk \
    # Use a specific version that's known to work with Zig 0.14.0
    && ./emsdk install 3.1.45 \
    && ./emsdk activate 3.1.45 \
    # Don't create symlinks to system tools - let Emscripten use its own tools
    && chmod +x /opt/emsdk/emsdk_env.sh \
    && . /opt/emsdk/emsdk_env.sh

# Set environment variables for Emscripten
ENV PATH="/opt/emsdk:/opt/emsdk/upstream/emscripten:/opt/emsdk/node/current/bin:/opt/emsdk/upstream/bin:${PATH}"
ENV EMSDK="/opt/emsdk"
ENV EM_CONFIG="/opt/emsdk/.emscripten"
# Verify emcc can run
RUN . /opt/emsdk/emsdk_env.sh && emcc --version

# Create necessary directories
RUN mkdir -p /games /hashes /config /scripts

# Copy configuration files
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY web/ /usr/share/nginx/html/
COPY games.json /config/games.json
COPY scripts/ /scripts/

# # Fix Xvfb display lock issue
# RUN echo '#!/bin/bash\n\
# # Remove any existing lock file for display 99\n\
# if [ -f /tmp/.X99-lock ]; then\n\
#     rm -f /tmp/.X99-lock\n\
# fi\n\
# Xvfb :99 -screen 0 1024x768x24 &\n\
# export DISPLAY=:99\n\
# # Start other services\n\
# echo "Starting nginx..."\n\
# nginx\n\
# echo "WASM Game Directory is ready."\n\
# echo "Container is now running. Press Ctrl+C to stop."\n\
# # Keep container running\n\
# tail -f /dev/null\n' > /scripts/entrypoint.sh

# Make scripts executable
RUN chmod +x /scripts/*.sh

# Expose port
EXPOSE 80

# Entry script to start services
ENTRYPOINT ["/scripts/entrypoint.sh"]
