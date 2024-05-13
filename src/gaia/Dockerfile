# Use Alpine Linux for the final image
FROM alpine:latest as base

# Install necessary packages
RUN apk add --no-cache ca-certificates curl bash

# Set environment variables
ENV GAIA_VERSION=v15.2.0 \
    GAIA_BINARY_NAME=gaiad-v15.2.0-linux-amd64 \
    GAIA_HOME=/opt/gaia

# Create directories
RUN mkdir -p $GAIA_HOME/bin

# Download the gaiad binary
RUN curl -Lo $GAIA_HOME/bin/gaiad https://github.com/cosmos/gaia/releases/download/$GAIA_VERSION/$GAIA_BINARY_NAME

# Make the binary executable
RUN chmod +x $GAIA_HOME/bin/gaiad

# Add the binary to PATH
ENV PATH=$PATH:$GAIA_HOME/bin

# Expose the necessary ports
EXPOSE 26656 26657 9080 9081 6050

# Set a command or script that keeps the container running
CMD ["sleep", "infinity"]
