FROM bash:5

# Install dependencies for the bash script and add Python for the server
RUN apk add --no-cache wget tar xz jq mkvtoolnix python3

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
# Ensure extract_ass_to_srt.sh and http_handler.py are in the same directory as the Dockerfile
COPY extractor.sh .
COPY server.py .

# Make the scripts executable
RUN chmod +x extractor.sh server.py

# Set the default listening port for the server (can be overridden at runtime)
ENV LISTEN_PORT=8080

# Expose the port to the host
EXPOSE 8080

# Set the default command to run the HTTP server when the container starts
CMD ["python3", "/scripts/server.py"]
