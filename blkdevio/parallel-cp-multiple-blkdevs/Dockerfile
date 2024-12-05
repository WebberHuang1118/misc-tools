# Use an official lightweight Linux distribution as the base
FROM alpine:latest

# Install the required tools: coreutils (includes dd and md5sum) and parallel
RUN apk add --no-cache coreutils parallel bash

# Copy the script into the container
COPY copy_and_verify.sh /usr/local/bin/copy_and_verify.sh

# Make the script executable
RUN chmod +x /usr/local/bin/copy_and_verify.sh

# Set the script as the entry point
ENTRYPOINT ["/usr/local/bin/copy_and_verify.sh"]
