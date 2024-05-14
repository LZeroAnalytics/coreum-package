# Use Ubuntu for the final image
FROM ubuntu:latest as base

# Install necessary packages
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    bash \
    unzip \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y

# Set environment variables
ENV HERMES_VERSION=v1.8.2 \
    HERMES_BINARY_NAME=hermes-v1.8.2-x86_64-unknown-linux-gnu.zip \
    HERMES_HOME=/opt/hermes \
    PATH=/root/.cargo/bin:$PATH

# Create directories
RUN mkdir -p $HERMES_HOME/bin

# Download the Hermes binary archive
RUN curl -Lo /tmp/$HERMES_BINARY_NAME https://github.com/informalsystems/hermes/releases/download/$HERMES_VERSION/$HERMES_BINARY_NAME

# Extract the binary archive
RUN unzip /tmp/$HERMES_BINARY_NAME -d $HERMES_HOME/bin/

# Make the binary executable
RUN chmod +x $HERMES_HOME/bin/hermes

# Add the binary to PATH
ENV PATH=$PATH:$HERMES_HOME/bin

# Expose the necessary telemetry port
EXPOSE 7698

# Set a command or script that keeps the container running
CMD ["sleep", "infinity"]