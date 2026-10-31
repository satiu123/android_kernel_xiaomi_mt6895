FROM docker.io/library/ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bc \
    bison \
    build-essential \
    ccache \
    curl \
    flex \
    gcc-aarch64-linux-gnu \
    git \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    lz4 \
    make \
    python3 \
    python-is-python3 \
    rsync \
    unzip \
    zip \
    zstd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /kernel
