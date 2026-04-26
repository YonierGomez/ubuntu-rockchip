#!/bin/bash

set -eE 
trap 'echo Error: in $0 on line $LINENO' ERR

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

# shellcheck source=/dev/null
source "../config/boards/${BOARD}.sh"

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

if [[ ${LAUNCHPAD} != "Y" ]]; then
    uboot_package="$(basename "$(find u-boot-"${BOARD}"_*.deb | sort | tail -n1)")"
    if [ ! -e "$uboot_package" ]; then
        echo 'Error: could not find the u-boot package'
        exit 1
    fi

    # Exclude debug packages (-dbg) so we install only the main image
    linux_image_package="$(basename "$(find linux-image-*.deb ! -name '*-dbg_*' | sort | tail -n1)")"
    if [ ! -e "$linux_image_package" ]; then
        echo "Error: could not find the linux image package"
        exit 1
    fi

    linux_headers_package="$(basename "$(find linux-headers-*.deb | sort | tail -n1)")"
    if [ ! -e "$linux_headers_package" ]; then
        echo "Error: could not find the linux headers package"
        exit 1
    fi

    # Mainline bindeb-pkg bundles modules into linux-image — these extra packages
    # only exist in the Joshua Riek kernel fork. Make them optional.
    linux_modules_package="$(basename "$(find linux-modules-*.deb 2>/dev/null | sort | tail -n1)")" || true
    linux_buildinfo_package="$(basename "$(find linux-buildinfo-*.deb 2>/dev/null | sort | tail -n1)")" || true
    linux_rockchip_headers_package="$(basename "$(find linux-rockchip-headers-*.deb 2>/dev/null | sort | tail -n1)")" || true
fi

setup_mountpoint() {
    local mountpoint="$1"

    if [ ! -c /dev/mem ]; then
        mknod -m 660 /dev/mem c 1 1
        chown root:kmem /dev/mem
    fi

    mount dev-live -t devtmpfs "$mountpoint/dev"
    mount devpts-live -t devpts -o nodev,nosuid "$mountpoint/dev/pts"
    mount proc-live -t proc "$mountpoint/proc"
    mount sysfs-live -t sysfs "$mountpoint/sys"
    mount securityfs -t securityfs "$mountpoint/sys/kernel/security"
    # Provide more up to date apparmor features, matching target kernel
    # cgroup2 mount for LP: 1944004
    mount -t cgroup2 none "$mountpoint/sys/fs/cgroup"
    mount -t tmpfs none "$mountpoint/tmp"
    mount -t tmpfs none "$mountpoint/var/lib/apt/lists"
    mount -t tmpfs none "$mountpoint/var/cache/apt"
    mv "$mountpoint/etc/resolv.conf" resolv.conf.tmp
    cp /etc/resolv.conf "$mountpoint/etc/resolv.conf"
    mv "$mountpoint/etc/nsswitch.conf" nsswitch.conf.tmp
    sed 's/systemd//g' nsswitch.conf.tmp > "$mountpoint/etc/nsswitch.conf"
}

teardown_mountpoint() {
    # Reverse the operations from setup_mountpoint
    local mountpoint
    mountpoint=$(realpath "$1")

    # ensure we have exactly one trailing slash, and escape all slashes for awk
    mountpoint_match=$(echo "$mountpoint" | sed -e's,/$,,; s,/,\\/,g;')'\/'
    # sort -r ensures that deeper mountpoints are unmounted first
    awk </proc/self/mounts "\$2 ~ /$mountpoint_match/ { print \$2 }" | LC_ALL=C sort -r | while IFS= read -r submount; do
        mount --make-private "$submount"
        umount "$submount"
    done
    mv resolv.conf.tmp "$mountpoint/etc/resolv.conf"
    mv nsswitch.conf.tmp "$mountpoint/etc/nsswitch.conf"
}

# Prevent dpkg interactive dialogues
export DEBIAN_FRONTEND=noninteractive

# Override localisation settings to address a perl warning
export LC_ALL=C

# Debootstrap options
chroot_dir=rootfs
overlay_dir=../overlay

# Extract the compressed root filesystem
rm -rf ${chroot_dir} && mkdir -p ${chroot_dir}
tar -xpJf "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64.rootfs.tar.xz" -C ${chroot_dir}

# Mount the root filesystem
setup_mountpoint $chroot_dir

# Update packages
chroot $chroot_dir apt-get update
chroot $chroot_dir apt-get -y upgrade
    
# Run config hook to handle board specific changes
if [[ $(type -t config_image_hook__"${BOARD}") == function ]]; then
    config_image_hook__"${BOARD}" "${chroot_dir}" "${overlay_dir}" "${SUITE}"
fi 

# Download and install U-Boot
if [[ ${LAUNCHPAD} == "Y" ]]; then
    chroot ${chroot_dir} apt-get -y install "u-boot-${BOARD}"
else
    cp "${uboot_package}" ${chroot_dir}/tmp/
    # dpkg -i may fail if dependencies aren't satisfied; resolve with apt-get -f
    chroot ${chroot_dir} dpkg -i "/tmp/${uboot_package}" || chroot ${chroot_dir} apt-get install -y -f
    chroot ${chroot_dir} apt-mark hold "$(echo "${uboot_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"

    # Build list of kernel debs that actually exist (mainline only has image+headers)
    kernel_debs=("${linux_image_package}" "${linux_headers_package}")
    for optional in "${linux_modules_package}" "${linux_buildinfo_package}" "${linux_rockchip_headers_package}"; do
        [ -n "$optional" ] && [ -e "$optional" ] && kernel_debs+=("$optional")
    done

    cp "${kernel_debs[@]}" ${chroot_dir}/tmp/
    chroot ${chroot_dir} /bin/bash -c "apt-get -y purge \$(dpkg --list | grep -Ei 'linux-image|linux-headers|linux-modules|linux-rockchip' | awk '{ print \$2 }') || true"
    chroot ${chroot_dir} /bin/bash -c "dpkg -i $(printf '/tmp/%s ' "${kernel_debs[@]}")" \
        || chroot ${chroot_dir} apt-get install -y -f
    chroot ${chroot_dir} apt-mark hold "$(echo "${linux_image_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"
fi

# Mainline bindeb-pkg installs DTBs under /usr/lib/linux-image-VERSION/
# but U-Boot extlinux looks for them under /lib/firmware/VERSION/device-tree/
# (this is where Joshua Riek's official image places them, matches Debian kernel layout)
kernel_version=$(echo "${linux_image_package}" | sed -rn 's/linux-image-(.*)_[[:digit:]].*/\1/p')
dtb_src="${chroot_dir}/usr/lib/linux-image-${kernel_version}"
dtb_dst="${chroot_dir}/lib/firmware/${kernel_version}/device-tree"
if [ -d "${dtb_src}" ]; then
    mkdir -p "${dtb_dst}"
    cp -r "${dtb_src}"/* "${dtb_dst}/"
fi

# Configure /etc/default/u-boot so that u-boot-update generates extlinux.conf
# with the correct parameters for Rockchip boards. u-boot-update runs later
# in build-image.sh after the rootfs is installed, so writing extlinux.conf
# directly would be overwritten — this is the proper way to customize it.
cat > "${chroot_dir}/etc/default/u-boot" <<EOF
## /etc/default/u-boot - configuration file for u-boot-update(8)

U_BOOT_PROMPT="1"
U_BOOT_TIMEOUT="20"
U_BOOT_PARAMETERS="rootwait rw console=ttyS2,1500000 console=tty1 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"
U_BOOT_FDT_DIR="/lib/firmware/"
U_BOOT_MENU_LABEL="Ubuntu ${RELASE_VERSION} LTS"
EOF

# Update the initramfs
chroot ${chroot_dir} update-initramfs -u

# Remove packages
chroot ${chroot_dir} apt-get -y clean
chroot ${chroot_dir} apt-get -y autoclean
chroot ${chroot_dir} apt-get -y autoremove

# Umount the root filesystem
teardown_mountpoint $chroot_dir

# Compress the root filesystem and then build a disk image
cd ${chroot_dir} && tar -cpf "../ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64-${BOARD}.rootfs.tar" . && cd .. && rm -rf ${chroot_dir}
../scripts/build-image.sh "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64-${BOARD}.rootfs.tar"
rm -f "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64-${BOARD}.rootfs.tar"
