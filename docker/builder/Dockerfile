FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        libfmt-dev \
        libspdlog-dev \
        ninja-build \
        pkg-config \
        python3 \
        qt6-base-dev \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8

# Only the build driver is part of the image. Compose mounts the sources.
COPY build.sh /usr/local/bin/build-emulatr
WORKDIR /workspace
CMD ["bash", "/usr/local/bin/build-emulatr"]
