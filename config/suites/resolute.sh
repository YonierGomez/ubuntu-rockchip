# shellcheck shell=bash

export RELASE_NAME="Ubuntu 26.04 LTS (Resolute Raccoon)"
export RELASE_VERSION="26.04"

export KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
# master has post-v7.0 HDMI/VOP2 fixes for RK3588. v7.0 tag from Feb 2026 had
# rk3588-orangepi-5-max.dts but was missing HDMI audio + display improvements
# merged in the following weeks.
export KERNEL_BRANCH="master"
export KERNEL_FLAVOR="generic"

export EXTRA_PPAS="jjriek/rockchip jjriek/rockchip-multimedia"
