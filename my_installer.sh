#!/bin/sh
set -e

target_disk=${1}
efi_size=512M
swap_size=4G
tarball_path1='https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds'
tarball_path2='/current-stage3-amd64-desktop-systemd'

echo "Creating partitions"
sgdisk -Z ${target_disk}
sgdisk -o ${target_disk}
sgdisk -n 1:0:+${efi_size} -t 1:ef00 ${target_disk}
sgdisk -n 2:0:-${swap_size} -t 2:8300 ${target_disk}
sgdisk -n 3:0: -t 3:8200 ${target_disk}

echo "Creating file systems"
mkfs.vfat -F32 ${target_disk}/1
mkfs.ext4 ${target_disk}/2
mkswap ${target_disk}/3

echo "Mounting partitions"
mount ${target_disk}/2 /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount ${target_disk}/1 /mnt/gentoo/boot
swapon ${target_disk}/3

echo "Move directory"
cd /mnt/gentoo

echo "Download stage3 tarball"
tarball_path3=$(curl -s ${tarball_path1}'/latest-stage3-amd64-desktop-systemd.txt' | grep -v '^#' | a    wk '{print substr($1, index($1,"/"))}') 
tarball_url=${tarball_path1}${tarball_path2}${tarball_path3}
wget "${tarball_url}"

echo "Unpacking the stage tarball"
tar xpvf $(basename ${tarball_url}) --xattrs-include='*.*' --numeric-owner

echo "Configuring compile options"
cat << EOF > /mnt/gentoo/etc/portage/make.conf
# These settings were set by the catalyst build script that automatically
# built this stage.
# Please consult /usr/share/portage/config/make.conf.example for a more
# detailed example.
COMMON_FLAGS="-march=native -O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
MAKEOPTS="-j6"
ACCEPT_LICENSE="*"
# ACCEPT_KEYWORDS="~amd64"
EMERGE_DEFAULT_OPTS="--ask --verbose"
USE="X nvidia intel xinerama initramfs hscolour cjk perl python"

# NOTE: This stage was built with the bindist Use flag enabled
PORTDIR="/var/db/repos/gentoo"
DISTDIR="/var/cache/distfiles"
PKGDIR="/var/cache/binpkgs"

# This sets the language of build output to English.
# Please keep this setting intact when reporting bugs.
LC_MESSAGES=C
LINGUAS="en ja"
L10N="en ja"

INPUT_DEVICES="libinput"
VIDEO_CARDS="nvidia nouveau intel"
GRUB_PLATFORMS="efi-64"

GENTOO_MIRRORS="http://ftp.iij.ad.jp/pub/linux/gentoo/ ftp://ftp.iij.ad.jp/pub/linux/gentoo/ https://ftp.jaist.ac.jp/pub/Linux/Gentoo/ http://ftp.jaist.ac.jp/pub/Linux/Gentoo/ ftp://ftp.jaist.ac.jp/pub/Linux/Gentoo/ https://ftp.riken.jp/Linux/gentoo/ http://ftp.riken.jp/Linux/gentoo/"
EOF

echo "Configuring the Gentoo ebuild repository"
mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf

echo "Copy DNS info"
cp --dereference /etc/resolv.conf /mnt/gentoo/etc

echo "Mounting the necessary filesystems"
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount -bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

echo "Entering the new environment"
chroot /mnt/gentoo /bin/bash -s << EOF
#!/bin/sh
set -e

source /etc/profile
export PS1="(chroot) ${PS1}"

echo "Configuring Portage"
emerge-webrsync
emerge --ask --verbose --update --deep --newuse @world
