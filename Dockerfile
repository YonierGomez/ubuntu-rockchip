FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    gcc-aarch64-linux-gnu \
    bison \
    qemu-user \
    qemu-user-binfmt \
    qemu-system-arm \
    qemu-efi-aarch64 \
    qemu-utils \
    flex \
    libssl-dev \
    bc \
    kmod \
    cpio \
    libncurses-dev \
    libelf-dev \
    libdw-dev \
    debhelper \
    fakeroot \
    python3 \
    python3-dev \
    python3-setuptools \
    python3-pyelftools \
    python3-yaml \
    swig \
    libpython3-dev \
    device-tree-compiler \
    parted \
    debootstrap \
    dosfstools \
    rsync \
    wget \
    curl \
    xz-utils \
    pixz \
    pigz \
    pbzip2 \
    uuid-dev \
    libgnutls28-dev \
    u-boot-tools \
    udev \
    kpartx \
    mount \
    util-linux \
    fdisk \
    gdisk \
    e2fsprogs \
    dosfstools \
    uuid-runtime \
    sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

CMD ["/bin/bash"]
