#!/bin/sh

set -eu

# Variables
partition=${1}
EFI_filesystem_size='512M'
SWAP_filesystem_size='4G'
gentoo_tarball_URL1='https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds/current-stage3-amd64-desktop-systemd/stage3-amd64-desktop-systemd-'
gentoo_tarball_URL2='.tar.xz'
make_conf=''

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
   wget ${gentoo_tarball_URL1} .* ${gentoo_tarball_URL2}
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

# Main
partitioning
format
mount_partitions
cd /mnt/gentoo
download_stage_tarball
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
echo make_conf > /mnt/gentoo/etc/portage/make.make_conf
mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount_filesystems
