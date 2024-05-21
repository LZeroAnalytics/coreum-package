# Use Alpine Linux for the final image
FROM alpine:latest as base

# Install necessary packages
RUN apk add --no-cache ca-certificates curl bash

# Set environment variables
ENV COREUM_VERSION=v3.0.3 \
    COREUM_BINARY_NAME=cored-linux-amd64 \
    COREUM_HOME=/opt/coreum

# Create directories
RUN mkdir -p $COREUM_HOME/bin

# Download the cored binary
RUN curl -Lo $COREUM_HOME/bin/cored https://github.com/CoreumFoundation/coreum/releases/download/$COREUM_VERSION/$COREUM_BINARY_NAME

# Make the binary executable
RUN chmod +x $COREUM_HOME/bin/cored

# Add the binary to PATH
ENV PATH=$PATH:$COREUM_HOME/bin

# Expose the necessary ports (adjust these if needed based on the application requirements)
EXPOSE 26656 26657 9090 9091 1317 6060 26660

# Set a command or script that keeps the container running since the ENTRYPOINT is not starting the node
CMD ["tail", "-f", "/dev/null"]
