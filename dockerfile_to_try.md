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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

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
ENV PATH="/opt/emsdk:/opt/emsdk/upstream/emscripten:${PATH}"
ENV EMSDK="/opt/emsdk"

# Create directories for Zig project and Nginx web server
RUN mkdir -p /app/zig-project
RUN mkdir -p /var/www/html

# Configure Nginx
RUN echo 'server {\n\
    listen 80;\n\
    server_name localhost;\n\
    location / {\n\
        root /var/www/html;\n\
        index index.html;\n\
        try_files $uri $uri/ =404;\n\
    }\n\
}' > /etc/nginx/sites-available/default

# Set working directory
WORKDIR /app/zig-project

# Copy your Zig project (to be added at build time with the appropriate context)
# COPY . .

# Entry point script
RUN echo '#!/bin/bash\n\
# Source Emscripten environment\n\
source /opt/emsdk/emsdk_env.sh\n\
\n\
# Build the Zig project\n\
cd /app/zig-project\n\
zig build deploy\n\
\n\
# Copy build artifacts to Nginx web root (adjust path as needed)\n\
# Assuming the WASM output is in a specific directory - adjust as needed\n\
cp -r /app/zig-project/zig-out/* /var/www/html/\n\
\n\
# Start Nginx in foreground\n\
nginx -g "daemon off;"\n\
' > /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh

# Expose port for Nginx
EXPOSE 80

# Run the entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]