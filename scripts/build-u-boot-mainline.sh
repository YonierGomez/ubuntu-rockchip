#!/bin/bash

set -eE
trap 'echo "Error: in $0 on line $LINENO (cmd: $BASH_COMMAND)"' ERR

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

cd "$(dirname -- "$(readlink -f -- "$0")")" && cd ..
mkdir -p build && cd build

if [[ -z ${BOARD} ]]; then
    echo "Error: BOARD is not set"
    exit 1
fi

# Mainline U-Boot tag that has orangepi-5-max-rk3588_defconfig
UBOOT_REPO="https://github.com/u-boot/u-boot.git"
UBOOT_TAG="v2025.07"
UBOOT_DEFCONFIG="orangepi-5-max-rk3588_defconfig"

# Rockchip firmware blobs (DDR init + BL31 ARM Trusted Firmware)
RKBIN_REPO="https://github.com/rockchip-linux/rkbin.git"
# Blob versions are auto-detected from rkbin/bin/rk35/ (newest by sort -V)

echo "=== Building mainline U-Boot ${UBOOT_TAG} for ${BOARD} ==="

# Clone rkbin (firmware blobs)
if [ ! -d rkbin ]; then
    git clone --depth=1 "${RKBIN_REPO}" rkbin
fi

# Clone U-Boot mainline
if [ ! -d u-boot-mainline ]; then
    git clone --depth=1 --branch "${UBOOT_TAG}" "${UBOOT_REPO}" u-boot-mainline
fi

cd u-boot-mainline

# Auto-detect newest available blobs (Rockchip releases updated versions over time).
RKBIN_DIR="${PWD}/../rkbin/bin/rk35"
RKBIN_BL31_PATH=$(ls "${RKBIN_DIR}"/rk3588_bl31_v*.elf 2>/dev/null | sort -V | tail -n1)
RKBIN_DDR_PATH=$(ls "${RKBIN_DIR}"/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v*.bin 2>/dev/null | grep -v eyescan | sort -V | tail -n1)

if [ -z "${RKBIN_BL31_PATH}" ]; then
    echo "Error: No rk3588_bl31_v*.elf found in ${RKBIN_DIR}"
    ls "${RKBIN_DIR}" | head
    exit 1
fi
if [ -z "${RKBIN_DDR_PATH}" ]; then
    echo "Error: No rk3588_ddr_*.bin found in ${RKBIN_DIR}"
    ls "${RKBIN_DIR}" | head
    exit 1
fi

# shellcheck disable=SC2046
export $(dpkg-architecture -aarm64)
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm
export BL31="${RKBIN_BL31_PATH}"
export ROCKCHIP_TPL="${RKBIN_DDR_PATH}"

echo "=== BL31:  ${BL31}"
echo "=== TPL:   ${ROCKCHIP_TPL}"
echo "=== Configuring: ${UBOOT_DEFCONFIG}"

make distclean
make "${UBOOT_DEFCONFIG}"

echo "=== Building ==="
make -j"$(nproc)"

echo "=== Verifying artifacts ==="
ls -lh u-boot-rockchip.bin idbloader.img u-boot.itb 2>/dev/null || true

# u-boot-rockchip.bin is the combined image that goes to sector 64 (32k offset)
# It contains: idbloader + u-boot.itb in the correct layout
if [ ! -f u-boot-rockchip.bin ]; then
    echo "Error: u-boot-rockchip.bin was not produced"
    exit 1
fi

echo "=== Done. u-boot-rockchip.bin ready ==="
echo "Write to disk with: dd if=u-boot-rockchip.bin of=/dev/DISK bs=32k seek=1 conv=fsync"
