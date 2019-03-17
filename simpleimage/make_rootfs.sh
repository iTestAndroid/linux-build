#!/bin/bash
#
# Simple script to create a rootfs for aarch64 platforms including support
# for Kernel modules created by the rest of the scripting found in this
# module.
#
# Use this script to populate the second partition of disk images created with
# the simpleimage script of this project.
#

set -e

BUILD="../build"
DEST="$1"
LINUX="$2"
PACKAGEDEB="$3"
DISTRO="$4"
BOOT="$5"
MODEL="$6"
VARIANT="$7"
RELEASE_REPO=ayufan-rock64/linux-rootfs
BUILD_ARCH=arm64

if [ -z "$MODEL" ]; then
  MODEL="pine64"
fi

export LC_ALL=C

if [ -z "$DEST" ]; then
	echo "Usage: $0 <destination-folder> [<linux-tarball>] <package.deb> [distro] [<boot-folder>] [model] [variant: mate, i3 or empty]"
	exit 1
fi

if [ "$(id -u)" -ne "0" ]; then
	echo "This script requires root."
	exit 1
fi

DEST=$(readlink -f "$DEST")
if [ -n "$LINUX" -a "$LINUX" != "-" ]; then
	LINUX=$(readlink -f "$LINUX")
fi

if [ ! -d "$DEST" ]; then
	echo "Destination $DEST not found or not a directory."
	exit 1
fi

if [ "$(ls -A -Ilost+found $DEST)" ]; then
	echo "Destination $DEST is not empty. Aborting."
	exit 1
fi

if [ -z "$DISTRO" ]; then
	DISTRO="xenial"
fi

if [ -n "$BOOT" ]; then
	BOOT=$(readlink -f "$BOOT")
fi

TEMP=$(mktemp -d)
cleanup() {
	if [ -e "$DEST/proc/cmdline" ]; then
		umount "$DEST/proc"
	fi
	if [ -d "$DEST/sys/kernel" ]; then
		umount "$DEST/sys"
	fi
	umount "$DEST/tmp" || true
	if [ -d "$TEMP" ]; then
		rm -rf "$TEMP"
	fi
}
trap cleanup EXIT

ROOTFS=""
TAR_OPTIONS=""

case $DISTRO in
	arch)
		ROOTFS="http://archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
		TAR_OPTIONS="-z"
		;;
	xenial|bionic)
		version=$(curl -s https://api.github.com/repos/$RELEASE_REPO/releases/latest | jq -r ".tag_name")
		ROOTFS="https://github.com/$RELEASE_REPO/releases/download/${version}/ubuntu-${DISTRO}-${VARIANT}-${version}-${BUILD_ARCH}.tar.xz"
		FALLBACK_ROOTFS="https://github.com/$RELEASE_REPO/releases/download/${version}/ubuntu-${DISTRO}-minimal-${version}-${BUILD_ARCH}.tar.xz"
		TAR_OPTIONS="-J --strip-components=1 binary"
		;;
	sid|stretch)
		version=$(curl -s https://api.github.com/repos/$RELEASE_REPO/releases/latest | jq -r ".tag_name")
		ROOTFS="https://github.com/$RELEASE_REPO/releases/download/${version}/debian-${DISTRO}-${VARIANT}-${version}-${BUILD_ARCH}.tar.xz"
		FALLBACK_ROOTFS="https://github.com/$RELEASE_REPO/releases/download/${version}/debian-${DISTRO}-minimal-${version}-${BUILD_ARCH}.tar.xz"
		TAR_OPTIONS="-J --strip-components=1 binary"
		;;
	*)
		echo "Unknown distribution: $DISTRO"
		exit 1
		;;
esac

CACHE_ROOT="${CACHE_ROOT:-tmp}"
mkdir -p "$CACHE_ROOT"
TARBALL="${CACHE_ROOT}/$(basename $ROOTFS)"

if [ ! -e "$TARBALL" ]; then
	echo "Downloading $DISTRO rootfs tarball ..."
	pushd "$CACHE_ROOT"
	if ! flock "$(basename "$ROOTFS").lock" wget -c "$ROOTFS"; then
		TARBALL="${CACHE_ROOT}/$(basename "$FALLBACK_ROOTFS")"
		echo "Downloading fallback $DISTRO rootfs tarball ..."
		flock "$(basename "$FALLBACK_ROOTFS").lock" wget -c "$FALLBACK_ROOTFS"
	fi
	popd
fi

# Extract with BSD tar
echo -n "Extracting ... "
set -x
tar -xf "$TARBALL" -C "$DEST" $TAR_OPTIONS
echo "OK"

# Add qemu emulation.
cp /usr/bin/qemu-aarch64-static "$DEST/usr/bin"
cp /usr/bin/qemu-arm-static "$DEST/usr/bin"
echo -ne ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F" > "$DEST/usr/lib/binfmt.d/qemu-aarch64-static.conf"

# Prevent services from starting
cat > "$DEST/usr/sbin/policy-rc.d" <<EOF
#!/bin/sh
exit 101
EOF
chmod a+x "$DEST/usr/sbin/policy-rc.d"

do_chroot() {
	mount -o bind /tmp "$DEST/tmp"
	chroot "$DEST" mount -t proc proc /proc
	chroot "$DEST" mount -t sysfs sys /sys
	chroot "$DEST" $CHROOT_PREFIX "$@"
	chroot "$DEST" umount /sys
	chroot "$DEST" umount /proc
	umount "$DEST/tmp"
}

# Run stuff in new system.
case $DISTRO in
	arch)
		echo "No longer supported"
		exit 1
		;;
	xenial|bionic|sid|jessie|stretch)
		mv "$DEST/etc/resolv.conf" "$DEST/etc/resolv.conf.bak"
		cp /etc/resolv.conf "$DEST/etc/resolv.conf"
		DEB=ubuntu
		DEBUSER=pine64
		DEBUSERPW=pine64

		do_chroot apt-get -y update
		do_chroot apt-get -y install eatmydata

		export DEBIAN_FRONTEND=noninteractive
		export CHROOT_PREFIX="eatmydata --"

		do_chroot locale-gen en_US.UTF-8

		cat > "$DEST/second-phase" <<EOF
#!/bin/bash
set -ex
export DEBIAN_FRONTEND=noninteractive
locale-gen en_US.UTF-8
apt-get install -y software-properties-common dirmngr
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys BF428671
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 56A3D45E
if [[ "$DISTRO" == "stretch" ]]; then
	add-apt-repository "deb http://ppa.launchpad.net/longsleep/ubuntu-pine64-flavour-makers/ubuntu xenial main"
	add-apt-repository "deb http://ppa.launchpad.net/ayufan/pine64-ppa/ubuntu xenial main"
else
	add-apt-repository "deb http://ppa.launchpad.net/ayufan/pine64-ppa/ubuntu $DISTRO main"
fi
curl -fsSL http://deb.ayufan.eu/orgs/ayufan-pine64/archive.key | apt-key add -
apt-get -y update
apt-get -y install sudo sunxi-disp-tool \
	dosfstools curl xz-utils iw rfkill wpasupplicant openssh-server \
	alsa-utils nano git build-essential vim jq wget ca-certificates \
	htop figlet gdisk parted rsync
if [[ "$DISTRO" == "xenial" || "$DISTRO" == "bionic" ]]; then
	apt-get -y install landscape-common
fi
adduser --gecos $DEBUSER --disabled-login $DEBUSER --uid 1000
chown -R 1000:1000 /home/$DEBUSER
echo "$DEBUSER:$DEBUSERPW" | chpasswd
usermod -a -G sudo,adm,audio,input,video,plugdev $DEBUSER
apt-get -y autoremove
apt-get clean
EOF
		chmod +x "$DEST/second-phase"
		do_chroot /second-phase
		cat > "$DEST/etc/apt/sources.list.d/ayufan-pine64.list" <<EOF
deb http://deb.ayufan.eu/orgs/ayufan-pine64/releases /

# uncomment to use pre-release kernels and compatibility packages
# deb http://deb.ayufan.eu/orgs/ayufan-pine64/pre-releases /
EOF
		cat > "$DEST/etc/network/interfaces.d/eth0" <<EOF
allow-hotplug eth0
iface eth0 inet dhcp
EOF
		cat > "$DEST/etc/hostname" <<EOF
$MODEL
EOF
		cat > "$DEST/etc/pine64_model" <<EOF
$MODEL
EOF
		cat > "$DEST/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $MODEL

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
		cp $PACKAGEDEB $DEST/package.deb
		do_chroot dpkg -i "package.deb"
		do_chroot rm "package.deb"
		case "$VARIANT" in
			mate)
				do_chroot /usr/local/sbin/install_desktop.sh mate
				do_chroot systemctl set-default graphical.target
				do_chroot pine64_enable_sunxidrm.sh
				;;

			lxde)
				do_chroot /usr/local/sbin/install_desktop.sh lxde
				do_chroot systemctl set-default graphical.target
				do_chroot pine64_enable_sunxidrm.sh
				;;

			i3)
				do_chroot /usr/local/sbin/install_desktop.sh i3
				do_chroot systemctl set-default graphical.target
				do_chroot pine64_enable_sunxidrm.sh
				;;

			openmediavault)
				do_chroot /usr/local/sbin/install_openmediavault.sh
				;;
		esac
		do_chroot systemctl enable ssh-keygen
		if [ "$MODEL" = "pinebook" ] || [ "$MODEL" = "pinebook1080p" ]; then
			do_chroot systemctl enable pinebook-headphones
		fi
		sed -i 's|After=rc.local.service|#\0|;' "$DEST/lib/systemd/system/serial-getty@.service"
		rm -f "$DEST/second-phase"
		rm -f "$DEST/etc/resolv.conf"
		rm -f "$DEST"/etc/ssh/ssh_host_*
		mv "$DEST/etc/resolv.conf.bak" "$DEST/etc/resolv.conf"
		do_chroot apt-get -y autoremove
		do_chroot apt-get clean
		;;
	*)
		;;
esac

# Bring back folders
mkdir -p "$DEST/lib"
mkdir -p "$DEST/usr"

# Create fstab
cat <<EOF > "$DEST/etc/fstab"
# <file system>	<dir>	<type>	<options>			<dump>	<pass>
/dev/mmcblk0p1	/boot	vfat	defaults			0		2
/dev/mmcblk0p2	/	ext4	defaults,noatime		0		1
EOF

# Direct Kernel install
if [ -n "$LINUX" -a "$LINUX" != "-" -a -d "$LINUX" ]; then
	# NOTE(longsleep): Passing Kernel as folder is deprecated. Pass a tarball!

	mkdir "$DEST/lib/modules"
	# Install Kernel modules
	make -C $LINUX ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_install INSTALL_MOD_PATH="$DEST"
	# Install Kernel firmware
	make -C $LINUX ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- firmware_install INSTALL_MOD_PATH="$DEST"
	# Install Kernel headers
	make -C $LINUX ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- headers_install INSTALL_HDR_PATH="$DEST/usr"

	# Install extra mali module if found in Kernel tree.
	if [ -e $LINUX/modules/gpu/mali400/kernel_mode/driver/src/devicedrv/mali/mali.ko ]; then
		v=$(ls $DEST/lib/modules/)
		mkdir "$DEST/lib/modules/$v/kernel/extramodules"
		cp -v $LINUX/modules/gpu/mali400/kernel_mode/driver/src/devicedrv/mali/mali.ko $DEST/lib/modules/$v/kernel/extramodules
		depmod -b $DEST $v
	fi
elif [ -n "$LINUX" -a "$LINUX" != "-" ]; then
	# Install Kernel modules from tarball
	mkdir $TEMP/kernel
	tar -C $TEMP/kernel --numeric-owner -xJf "$LINUX"
	if [ -n "$BOOT" -a -e "$BOOT/uEnv.txt" ]; then
		# Install Kernel and uEnv.txt too.
		echo "Installing Kernel to boot $BOOT ..."
		rm -rf "$BOOT/pine64"
		rm -f "$BOOT/uEnv.txt"
		cp -RLp $TEMP/kernel/boot/* "$BOOT/"
		mv "$BOOT/uEnv.txt.in" "$BOOT/uEnv.txt"
	fi
	cp -RLp $TEMP/kernel/lib/* "$DEST/lib/" 2>/dev/null || true
	cp -RLp $TEMP/kernel/usr/* "$DEST/usr/"

	VERSION=""
	if [ -e "$TEMP/kernel/boot/Image.version" ]; then
		VERSION=$(cat $TEMP/kernel/boot/Image.version)
	fi

	if [ -n "$VERSION" ]; then
		# Create symlink to headers if not there.
		if [ ! -e "$DEST/lib/modules/$VERSION/build" ]; then
			ln -s /usr/src/linux-headers-$VERSION "$DEST/lib/modules/$VERSION/build"
		fi

		depmod -b $DEST $VERSION
	fi
fi

# Clean up
rm -f "$DEST/usr/bin/qemu-arm-static"
rm -f "$DEST/usr/bin/qemu-aarch64-static"
rm -f "$DEST/usr/sbin/policy-rc.d"
rm -f "$DEST/var/lib/dbus/machine-id"
rm -f "$DEST/SHA256SUMS"

echo "Done - installed rootfs to $DEST"
