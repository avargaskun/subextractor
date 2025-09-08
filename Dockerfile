# Use a standard Python base image which is based on Debian
FROM python:3.13.7-slim-bookworm

# Install dependencies using Debian's package manager (apt-get)
# We add 'bash' explicitly to ensure the shell script runs correctly.
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    tar \
    xz-utils \
    jq \
    mkvtoolnix \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Install ffmpeg and ffprobe statically
WORKDIR /tmp
RUN wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz \
    && tar -xJf ffmpeg-release-amd64-static.tar.xz \
    && mv ffmpeg-*-amd64-static/ffmpeg /usr/local/bin/ \
    && mv ffmpeg-*-amd64-static/ffprobe /usr/local/bin/ \
    && chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe \
    && rm -rf /tmp/*

# Create a directory for our scripts
WORKDIR /scripts

# Copy the scripts into the container
# Ensure extractor.sh and server.py are in the same directory as the Dockerfile
COPY extractor.sh .
COPY server.py .

# Make the scripts executable
RUN chmod +x extractor.sh server.py

# Set the default listening port for the server (can be overridden at runtime)
ENV LISTEN_PORT=8080

# Set the PYTHONUNBUFFERED environment variable to ensure logs are sent
# directly to the container's stdout without being held in a buffer.
ENV PYTHONUNBUFFERED=1

# Expose the port to the host
EXPOSE 8080

# Set the default command to run the HTTP server when the container starts
CMD ["python3", "/scripts/server.py"]

