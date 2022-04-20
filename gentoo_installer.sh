#!/bin/sh
set -eu

## variables
target_disk=$1
efi_size=512M
swap_size=8G
path_head="https://ftp.jaist.ac.jp/pub/Linux/Gentoo/releases/amd64/autobuilds/"
path_body="current-stage3-amd64-desktop-openrc/"
latest=${path_head}"latest-stage3-amd64-desktop-openrc.txt"
path_footer=$(curl -Ss ${latest} | grep -v '^#' | cut -d" " -f1)
path_tarball=${path_head}${path_body}${path_footer}
compile_opts=$(cat << EOF
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
# EMERGE_DEFAULT_OPTS="--ask --verbose"
# USE="X nvidia intel xinerama initramfs hscolour cjk perl python"
USE="xinerama initramfs"

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
VIDEO_CARDS="nvidia intel"
GRUB_PLATFORMS="efi-64"

GENTOO_MIRRORS="http://ftp.iij.ad.jp/pub/linux/gentoo/ ftp://ftp.iij.ad.jp/pub/linux/gentoo/ https://ftp.jaist.ac.jp/pub/Linux/Gentoo/ http://ftp.jaist.ac.jp/pub/Linux/Gentoo/ ftp://ftp.jaist.ac.jp/pub/Linux/Gentoo/ https://ftp.riken.jp/Linux/gentoo/ http://ftp.riken.jp/Linux/gentoo/"
EOF
)
host_name=$2

## main
echo "-------------------------
- Partitioning the disk -
-------------------------"
sgdisk -Z ${target_disk}
sgdisk -o ${target_disk}
sgdisk -n 1:0:+${efi_size} -t 1:ef00 ${target_disk}
sgdisk -n 2:0:-${swap_size} -t 2:8300 ${target_disk}
sgdisk -n 3:0: -t 3:8200 ${target_disk}

echo "-------------------------
- Creating file systems -
-------------------------"
mkfs.vfat -F32 ${target_disk}1
mkfs.ext4 ${target_disk}2
mkswap ${target_disk}3

echo "-----------------------
- Mounting partitions -
-----------------------"
swapon ${target_disk}
mount ${target_disk}2 /mnt/gentoo

echo "---------------------------------
- Downloading the stage tarball -
---------------------------------"
cd /mnt/gentoo
wget ${path_tarball}

echo "-------------------------------
- Unpacking the stage tarball -
-------------------------------"
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

echo "-------------------------------
- Configuring compile options -
-------------------------------"
echo ${compile_opts} > /mnt/gentoo/etc/portage/make.conf

echo "--------------------------------------------
- Configuring the gentoo ebuild repository -
--------------------------------------------"
mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf

echo "-----------------
- Copy DNS info -
-----------------"
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

echo "--------------------------------------
- Mounting the necessary filesystems -
--------------------------------------"
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run 

echo "--------------------------------
- Entering the new environment -
--------------------------------"
chroot /mnt/gentoo /bin/bash << EOT
source /etc/profile && export PS1="(chroot) ${PS1}"
mount /dev/sda1 /boot

echo "-------------------------------
- Mounting the boot partition -
-------------------------------"
mount /dev/sda1 /boot

echo "-----------------------
- Configuring Portage -
-----------------------"
emerge-webrsync

echo "------------
- Timezone -
------------"
echo "Asia/Tokyo" > /etc/timezone
emerge --config sys-libs/timezone-data

echo "---------------------
- Configure locales -
---------------------"
cat << EOF >> /etc/locale.gen
en_US.UTF-8 UTF-8
ja_JP.UTF-8 UTF-8
EOF
locale-gen
eselect locale set 4
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

echo "-------------------------------------
- Installing firmware and microcode -
-------------------------------------"
emerge sys-kernel/linux-firmware sys-firmware/intel-microcode

echo "--------------------------
- Installing the sources -
--------------------------"
emerge sys-kernel/gentoo-sources
eselect kernel set 1
emerge sys-kernel/genkernel
cat << EOF >> /etc/fstab
UUID=$(blkid -s UUID -o value ${target_disk}1)	/boot		vfat		defaults,noatime	0 2
EOF
genkernel --microcode-initramfs all

echo "---------------------------
- Creating the fstab file -
---------------------------"
cat << EOF >> /etc/fstab
UUID=$(blkid -s UUID -o value ${target_disk}2)	/		ext4		defaults,noatime	0 1
UUID=$(blkid -s UUID -o value ${target_disk}3)	none		swap		sw	0 0
/dev/cdrom	/mnt/cdrom	auto		noauto,user	0 0
EOF

echo "-------------------------
- network configuration -
-------------------------"
echo hostname=${host_name} > /etc/conf.d/hostname
echo dns_domain_lo="homenetwork" > /etc/conf.d/net
emerge net-misc/dhcpcd
rc-update add dhcpcd default
sed -e "s/127.0.0.1	localhost/127.0.0.1	${host_name}.homenetwork ${host_name} localhost" /etc/hosts > /etc/hosts

echo "---------------------------
- Installing system tools -
---------------------------"
emerge sys-process/cronie net-misc/chrony sys-fs/dosfstools
rc-update add cronie default
rc-update add chronyd default

echo "--------------------------
- Configuring bootloader -
--------------------------"
echo ">=sys-boot/grub-2.06-r1 mount" > /etc/portage/package.use/grub
emerge sys-boot/grub sys-boot/os-prober
grub-install --target=x86_64-efi --efi-directory=/boot --removable
echo GRUB_DISABLE_OS_PROBER=false >> /etc/default/grub
echo GRUB_EARLY_INITRD_LINUX_CUSTOM="ucode.cpio" >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

echo "-----------------------------------------
- Setting root password & reboot system -
- #passwd                               -
- #exit                                 -
- #cd                                   -
- #umount -l /mnt/gentoo/dev{/shm,/pts,}-
- #umount -R /mnt/gentoo                -
- #reboot                               -
-----------------------------------------"
echo "goodluck"
EOT
