#!/bin/sh

set -eu

# Variables
partition=${1}
EFI_filesystem_size='512M'
SWAP_filesystem_size='4G'

# Functions
function partitioning() {
   sgdisk -Z ${partition}
   sgdisk -o ${partition}
   sgdisk -n 1:0:+${EFI_filesystem_size} -t 1:ef00 ${partition}
   sgdisk -n 2:0:-${SWAP_filesystem_size} -t 2:8300 ${partition}
   sgdisk -n 3:0: -t 3:8200 ${partition}
}

function format() {
   mkfs.vfat -F32 ${partition}1
   mkfs.ext4 ${partition}2
   mkswap ${partition}3
}

function mount_partitions() {
   swapon ${partition}3
   mount ${partition}2 /mnt/gentoo
}

function download_stage_tarball() {
   gentoo_tarball_URL1='https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds'
   gentoo_tarball_URL2='/current-stage3-amd64-desktop-systemd'
   gentoo_tarball_URL3=$(curl ${URL1}'/latest-stage3-amd64-desktop-systemd.txt' | grep -v '^#' | awk '{print substr($1, index($1,"/"))}')
   gentoo_tarball_PATH="${gentoo_tarball_URL1}${gentoo_tarball_URL2}${gentoo_tarball_URL3}"
   wget "${gentoo_tarball_PATH}"
}

function mount_filesystems() {
   mount --types proc /proc /mnt/gentoo/proc
   mount --rbind /sys /mnt/gentoo/sys
   mount --make-rslave /mnt/gentoo/sys
   mount --rbind /dev /mnt/gentoo/dev
   mount --make-rslave /mnt/gentoo/dev
   mount --bind /run /mnt/gentoo/run
   mount --make-slave /mnt/gentoo/run
}

function make_conf() {
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
   ACCEPT_KEYWORDS="~amd64"
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
}

# Main
partitioning
format
mount_partitions
cd /mnt/gentoo
download_stage_tarball
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
make_conf
mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount_filesystems
