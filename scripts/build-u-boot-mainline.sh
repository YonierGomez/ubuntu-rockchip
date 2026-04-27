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
# Match what Armbian uses for RK3588
RKBIN_BL31="rk3588_bl31_v1.45.elf"
RKBIN_DDR="rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.16.bin"

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

# shellcheck disable=SC2046
export $(dpkg-architecture -aarm64)
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm
export BL31="${PWD}/../rkbin/bin/rk35/${RKBIN_BL31}"
export ROCKCHIP_TPL="${PWD}/../rkbin/bin/rk35/${RKBIN_DDR}"

# Verify blobs exist
if [ ! -f "${BL31}" ]; then
    echo "Error: BL31 not found at ${BL31}"
    ls "${PWD}/../rkbin/bin/rk35/" 2>/dev/null | grep bl31 | head
    exit 1
fi
if [ ! -f "${ROCKCHIP_TPL}" ]; then
    echo "Error: DDR blob not found at ${ROCKCHIP_TPL}"
    ls "${PWD}/../rkbin/bin/rk35/" 2>/dev/null | grep ddr | head
    exit 1
fi

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
