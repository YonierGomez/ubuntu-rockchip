#!/bin/bash

set -eE
trap 'echo Error: in $0 on line $LINENO' ERR

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

cd "$(dirname -- "$(readlink -f -- "$0")")" && cd ..
mkdir -p build && cd build

if [[ -z ${SUITE} ]]; then
    echo "Error: SUITE is not set"
    exit 1
fi

# shellcheck source=/dev/null
source "../config/suites/${SUITE}.sh"

if [[ -z ${FLAVOR} ]]; then
    echo "Error: FLAVOR is not set"
    exit 1
fi

# shellcheck source=/dev/null
source "../config/flavors/${FLAVOR}.sh"

ROOTFS_TAR="ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64.rootfs.tar.xz"

if [[ -f "${ROOTFS_TAR}" ]]; then
    exit 0
fi

CHROOT_DIR="$(mktemp -d)"
trap 'umount -lf "${CHROOT_DIR}/dev/pts" 2>/dev/null; umount -lf "${CHROOT_DIR}/dev" 2>/dev/null; umount -lf "${CHROOT_DIR}/proc" 2>/dev/null; umount -lf "${CHROOT_DIR}/sys" 2>/dev/null; umount -lf "${CHROOT_DIR}/tmp" 2>/dev/null; umount -lf "${CHROOT_DIR}/var/lib/apt/lists" 2>/dev/null; umount -lf "${CHROOT_DIR}/var/cache/apt" 2>/dev/null; rm -rf "${CHROOT_DIR}"' EXIT

echo "Bootstrapping Ubuntu ${RELASE_VERSION} (${SUITE}) arm64 rootfs..."

# Stage 1: minimal debootstrap
debootstrap \
    --arch=arm64 \
    --components=main,restricted,universe,multiverse \
    "${SUITE}" \
    "${CHROOT_DIR}" \
    "http://ports.ubuntu.com/ubuntu-ports"

# Mount pseudo-filesystems
mount -t devtmpfs  dev-live        "${CHROOT_DIR}/dev"
mount -t devpts    devpts-live     "${CHROOT_DIR}/dev/pts" -o nodev,nosuid
mount -t proc      proc-live       "${CHROOT_DIR}/proc"
mount -t sysfs     sysfs-live      "${CHROOT_DIR}/sys"
mount -t tmpfs     tmpfs-tmp       "${CHROOT_DIR}/tmp"
mount -t tmpfs     tmpfs-aptlists  "${CHROOT_DIR}/var/lib/apt/lists"
mount -t tmpfs     tmpfs-aptcache  "${CHROOT_DIR}/var/cache/apt"

cp /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# Configure apt sources
cat > "${CHROOT_DIR}/etc/apt/sources.list" <<EOF
deb http://ports.ubuntu.com/ubuntu-ports ${SUITE} main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports ${SUITE}-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports ${SUITE}-security main restricted universe multiverse
EOF

chroot "${CHROOT_DIR}" apt-get update
chroot "${CHROOT_DIR}" apt-get -y upgrade

# Install base packages in stages to avoid OOM in constrained build environments.
# linux-firmware is intentionally omitted here — it's ~500MB and gets installed
# later by config-image.sh alongside the board-specific kernel package.
chroot "${CHROOT_DIR}" apt-get -y install \
    sudo \
    locales \
    tzdata \
    systemd \
    systemd-sysv \
    initramfs-tools \
    openssh-server \
    net-tools \
    iproute2 \
    curl \
    wget

if [ "${FLAVOR}" == "server" ]; then
    chroot "${CHROOT_DIR}" apt-get -y install ubuntu-server
else
    chroot "${CHROOT_DIR}" apt-get -y install ubuntu-desktop-minimal
fi

# Set default locale
chroot "${CHROOT_DIR}" locale-gen en_US.UTF-8
chroot "${CHROOT_DIR}" update-locale LANG=en_US.UTF-8

# Set hostname
echo "ubuntu" > "${CHROOT_DIR}/etc/hostname"
cat > "${CHROOT_DIR}/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 ubuntu
EOF

# Create default ubuntu user (password: ubuntu)
chroot "${CHROOT_DIR}" useradd -m -s /bin/bash -G sudo ubuntu
echo "ubuntu:ubuntu" | chroot "${CHROOT_DIR}" chpasswd
chroot "${CHROOT_DIR}" passwd -e ubuntu

# Enable serial console for board bring-up
mkdir -p "${CHROOT_DIR}/etc/systemd/system/getty.target.wants"
chroot "${CHROOT_DIR}" systemctl enable serial-getty@ttyS2.service 2>/dev/null || true
chroot "${CHROOT_DIR}" systemctl enable serial-getty@ttyFIQ0.service 2>/dev/null || true

# Clean up apt caches
chroot "${CHROOT_DIR}" apt-get -y clean
chroot "${CHROOT_DIR}" apt-get -y autoremove

# Unmount pseudo-filesystems before tarring — sysfs/devtmpfs files are virtual
# and change size while being read, causing tar to fail or produce corrupted entries.
umount -lf "${CHROOT_DIR}/var/cache/apt"     2>/dev/null || true
umount -lf "${CHROOT_DIR}/var/lib/apt/lists" 2>/dev/null || true
umount -lf "${CHROOT_DIR}/tmp"               2>/dev/null || true
umount -lf "${CHROOT_DIR}/sys/kernel/security" 2>/dev/null || true
umount -lf "${CHROOT_DIR}/sys/fs/cgroup"     2>/dev/null || true
umount -lf "${CHROOT_DIR}/sys"               2>/dev/null || true
umount -lf "${CHROOT_DIR}/proc"              2>/dev/null || true
umount -lf "${CHROOT_DIR}/dev/pts"           2>/dev/null || true
umount -lf "${CHROOT_DIR}/dev"               2>/dev/null || true

echo "Compressing rootfs to ${ROOTFS_TAR}..."
# Exclude virtual FS mount points — they're empty dirs in the rootfs and get
# populated at boot by the kernel. Including them causes tar warnings.
# tar exits non-zero on warnings; use pipefail-safe construct to only fail on xz error.
set +o pipefail
(cd "${CHROOT_DIR}" && tar -cpf - --sort=name --xattrs \
    --exclude=./sys/* \
    --exclude=./proc/* \
    --exclude=./dev/* \
    --exclude=./tmp/* \
    --exclude=./run/* \
    ./* 2>/dev/null; exit 0) | xz -3 -T0 > "${ROOTFS_TAR}"
set -o pipefail
