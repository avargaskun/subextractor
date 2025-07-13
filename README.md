# SubExtractor Docker Image

A Docker image based on bash:5 with ffmpeg and mkvtoolnix installed for subtitle extraction and media processing.

## Features

- Base image: bash:5
- ffmpeg (static build from johnvansickle.com)
- mkvtoolnix package

## Usage

### Building locally
```bash
docker build -t subextractor .
```

### Running the container
```bash
# Run locally built image
docker run -it --rm -v $(pwd):/workspace subextractor

# Run from GitHub Container Registry
docker run -it --rm -v $(pwd):/workspace ghcr.io/yourusername/subextractor:latest
```

## GitHub Actions

The repository includes a GitHub Actions workflow that automatically builds and pushes the Docker image to GitHub Container Registry when changes are pushed to the main branch.

### Setup

No additional secrets are required - the workflow uses the built-in `GITHUB_TOKEN`. Simply push to the main branch to trigger the build and the image will be available at `ghcr.io/yourusername/subextractor`.

## Tools Available in Container

- `ffmpeg` - Video/audio processing
- `ffprobe` - Media file analysis  
- `mkvextract` - Extract tracks from MKV files
- `mkvinfo` - Display MKV file information
- All standard bash utilities