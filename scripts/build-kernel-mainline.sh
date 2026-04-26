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

echo "Building mainline kernel ${KERNEL_BRANCH} for RK3588..."

# Clone the mainline kernel repo
# Using tags (e.g. v7.0): fetch the tag explicitly since `git fetch origin <tag>`
# doesn't work the same as fetching a branch with --depth=1.
if [ -d "linux-mainline" ]; then
    cd linux-mainline
    git fetch --depth=1 origin "refs/tags/${KERNEL_BRANCH}:refs/tags/${KERNEL_BRANCH}" 2>/dev/null \
        || git fetch --depth=1 origin "${KERNEL_BRANCH}"
    git checkout "${KERNEL_BRANCH}"
else
    git clone --progress --depth=1 -b "${KERNEL_BRANCH}" "${KERNEL_REPO}" linux-mainline
    cd linux-mainline
fi

# shellcheck disable=SC2046
export $(dpkg-architecture -aarm64)
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64
export CC=aarch64-linux-gnu-gcc
export LANG=C
export LOCALVERSION=-rockchip

# Use defconfig for arm64 with Rockchip support
make defconfig

# Enable Rockchip RK3588 specific options for kernel 7.0+
# Core Rockchip support
scripts/config --enable CONFIG_ARCH_ROCKCHIP
scripts/config --enable CONFIG_ROCKCHIP_PM_DOMAINS
scripts/config --enable CONFIG_ROCKCHIP_IOMMU
scripts/config --enable CONFIG_ROCKCHIP_MBOX
scripts/config --enable CONFIG_ROCKCHIP_SARADC
scripts/config --enable CONFIG_ROCKCHIP_THERMAL

# PHY drivers (USB3, PCIe, HDMI support in 7.0)
scripts/config --enable CONFIG_PHY_ROCKCHIP_INNO_USB2
scripts/config --enable CONFIG_PHY_ROCKCHIP_NANENG_COMBO_PHY
scripts/config --enable CONFIG_PHY_ROCKCHIP_SAMSUNG_HDPTX
scripts/config --enable CONFIG_PHY_ROCKCHIP_SNPS_PCIE3
scripts/config --enable CONFIG_PHY_ROCKCHIP_USBDP

# Storage controllers
scripts/config --enable CONFIG_MMC_DW_ROCKCHIP
scripts/config --enable CONFIG_MMC_SDHCI_OF_DWCMSHC
scripts/config --enable CONFIG_PCIE_DW_ROCKCHIP
scripts/config --enable CONFIG_AHCI_DW

# Display support (HDMI support improved in 6.13/7.0)
scripts/config --enable CONFIG_DRM_ROCKCHIP
scripts/config --enable CONFIG_ROCKCHIP_VOP2
scripts/config --enable CONFIG_DRM_DISPLAY_CONNECTOR
scripts/config --enable CONFIG_DRM_DW_HDMI
scripts/config --enable CONFIG_DRM_DW_HDMI_QP
scripts/config --enable CONFIG_ROCKCHIP_LVDS
scripts/config --enable CONFIG_ROCKCHIP_RGB
scripts/config --enable CONFIG_DRM_ANALOGIX_ANX7625

# Audio support
scripts/config --enable CONFIG_SND_SOC_ROCKCHIP
scripts/config --enable CONFIG_SND_SOC_ROCKCHIP_I2S
scripts/config --enable CONFIG_SND_SOC_ROCKCHIP_I2S_TDM
scripts/config --enable CONFIG_SND_SOC_ROCKCHIP_SPDIF

# Clocks and power management
scripts/config --enable CONFIG_ROCKCHIP_RKTIMER
scripts/config --enable CONFIG_RTC_DRV_RK808
scripts/config --enable CONFIG_COMMON_CLK_RK808
scripts/config --enable CONFIG_COMMON_CLK_ROCKCHIP
scripts/config --enable CONFIG_CLK_RK3588

# GPIO and pinctrl
scripts/config --enable CONFIG_PINCTRL_ROCKCHIP
scripts/config --enable CONFIG_PINCTRL_RK805
scripts/config --enable CONFIG_GPIO_ROCKCHIP

# Regulators and power
scripts/config --enable CONFIG_REGULATOR_RK808
scripts/config --enable CONFIG_MFD_RK808

# I2C, SPI, PWM
scripts/config --enable CONFIG_I2C_RK3X
scripts/config --enable CONFIG_SPI_ROCKCHIP
scripts/config --enable CONFIG_SPI_ROCKCHIP_SFC
scripts/config --enable CONFIG_PWM_ROCKCHIP

# Watchdog and NVMEM
scripts/config --enable CONFIG_DW_WATCHDOG
scripts/config --enable CONFIG_ROCKCHIP_EFUSE
scripts/config --enable CONFIG_NVMEM_ROCKCHIP_OTP
scripts/config --enable CONFIG_ROCKCHIP_SIP

# USB support (all 3 USB3 controllers supported in 6.10+)
scripts/config --enable CONFIG_USB_DWC3
scripts/config --enable CONFIG_USB_DWC3_OF_SIMPLE
scripts/config --enable CONFIG_USB_OHCI_HCD
scripts/config --enable CONFIG_USB_OHCI_HCD_PLATFORM
scripts/config --enable CONFIG_USB_EHCI_HCD
scripts/config --enable CONFIG_USB_EHCI_HCD_PLATFORM
scripts/config --enable CONFIG_USB_XHCI_HCD
scripts/config --enable CONFIG_USB_XHCI_PLATFORM

# USB Type-C support
scripts/config --enable CONFIG_TYPEC
scripts/config --enable CONFIG_TYPEC_TCPM
scripts/config --enable CONFIG_TYPEC_FUSB302
scripts/config --enable CONFIG_EXTCON_USB_GPIO
scripts/config --enable CONFIG_PHY_ROCKCHIP_TYPEC

# Additional Rockchip features
scripts/config --enable CONFIG_ROCKCHIP_IODOMAIN
scripts/config --enable CONFIG_ROCKCHIP_GRF
scripts/config --enable CONFIG_ROCKCHIP_PVTM
scripts/config --enable CONFIG_CPU_RK3588

# CPU frequency scaling (added in 6.11)
scripts/config --enable CONFIG_ARM_RK3588_DMC_DEVFREQ
scripts/config --enable CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND
scripts/config --enable CONFIG_DEVFREQ_GOV_PERFORMANCE
scripts/config --enable CONFIG_DEVFREQ_GOV_POWERSAVE
scripts/config --enable CONFIG_DEVFREQ_GOV_USERSPACE
scripts/config --enable CONFIG_PM_DEVFREQ
scripts/config --enable CONFIG_ARM_SCMI_PROTOCOL
scripts/config --enable CONFIG_ARM_SCMI_POWER_DOMAIN
scripts/config --enable CONFIG_SENSORS_PWM_FAN

# Crypto acceleration
scripts/config --enable CONFIG_CRYPTO_DEV_ROCKCHIP

# Video acceleration (RGA2, VEPU121, VDPU121 in 6.12+)
scripts/config --enable CONFIG_VIDEO_ROCKCHIP_RGA
scripts/config --enable CONFIG_VIDEO_ROCKCHIP_VDEC
scripts/config --enable CONFIG_VIDEO_HANTRO
scripts/config --enable CONFIG_V4L2_MEM2MEM_DEV

# GPU support (Mali-G610 in 6.10+)
scripts/config --enable CONFIG_DRM_PANFROST
scripts/config --enable CONFIG_DRM_PANTHOR

# Network drivers commonly used on RK3588 boards
scripts/config --enable CONFIG_STMMAC_ETH
scripts/config --enable CONFIG_DWMAC_ROCKCHIP
scripts/config --enable CONFIG_R8169

# Enable module support
scripts/config --enable CONFIG_MODULES
scripts/config --enable CONFIG_MODULE_UNLOAD

# Regenerate config with dependencies
make olddefconfig

# Get kernel version
KERNEL_VERSION=$(make kernelversion)
echo "Kernel version: ${KERNEL_VERSION}"

# Build kernel, modules and device trees
make -j"$(nproc)" Image modules dtbs

# Remove any partial debian packaging artifacts from a previous failed run.
# bindeb-pkg creates ./debian/ internally; leftover directories can have
# execute-only permissions that block both chmod and tar on the next run.
rm -rf debian/

# cpio --dereference inside bindeb-pkg fails to resolve relative symlinks
# (e.g. ../../uapi/...) on Docker VirtioFS volume mounts, producing empty
# mode-000 files in the headers staging dir that tar cannot read.
# Fix: replace all file symlinks in the source tree with actual copies so
# cpio never needs to dereference anything.
find . -type l -not -path './.git/*' | while IFS= read -r link; do
    target=$(readlink -f "$link" 2>/dev/null)
    if [ -n "$target" ] && [ -f "$target" ] && [ -r "$target" ]; then
        cp --preserve=mode,timestamps "$target" "${link}.tmp" && mv "${link}.tmp" "$link"
    fi
done

chmod -R a+rX .

# Create debian packages — single-threaded to avoid dtbs_install race condition
# where parallel jobs try to create the same DTB subdirectory simultaneously.
KDEB_PKGVERSION="${KERNEL_VERSION}-1"
make -j1 bindeb-pkg KDEB_PKGVERSION="${KDEB_PKGVERSION}"

echo "Kernel packages created successfully!"
ls -lh ../*.deb
