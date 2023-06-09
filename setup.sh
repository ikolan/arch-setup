#! /bin/bash
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

set -e

clear
setfont ter-v16n
reflector --country France,Germany --save /etc/pacman.d/mirrorlist
sed -i "s/SigLevel.*$/SigLevel = Never/g" /etc/pacman.conf
pacman --noconfirm -Sy dialog

#
# PACKAGES
#

pkgs=(

# Base
base
base-devel
linux
linux-lts
linux-firmware
btrfs-progs
grub
efibootmgr
intel-ucode
amd-ucode
firewalld
networkmanager

# Shell
bash-completion
zsh
zsh-autosuggestions
zsh-completions
zsh-syntax-highlighting

# CLI tools
devtools
git
net-tools
openssh
pacman-contrib
pacutils
reflector
rsync
stow
tree
vim

# Desktop
xorg
plasma
sddm

# Audio
pipewire
pipewire-alsa
pipewire-audio
pipewire-jack
pipewire-pulse
pipewire-v4l2
pipewire-x11-bell
pipewire-zeroconf

# GUI Tools
ark
dolphin
filelight
firefox
firefox-i18n-fr
gwenview
kate
kfind
konsole
okular
partitionmanager
qpwgraph
skanlite

# Fonts
noto-fonts
noto-fonts-cjk
noto-fonts-emoji
noto-fonts-extra
terminus-font
ttf-roboto
ttf-roboto-mono
ttf-ubuntu-font-family

# Printing
cups
hplip
python-pyqt5

# Programming
rustup

# Other
hunspell
hunspell-fr

)

unpkgs=(

breeze-plymouth
discover
plasma-welcome
plymouth
plymouth-kcm

)

#
# FUNCTIONS
#

select_disk_part_dialog() {
    disks=$(lsblk -lp -o name,type | grep /dev)
    dialog --stdout --title "$1" --menu "" 0 0 0 $disks;
}

password_dialog() {
    dialog --stdout --title "$1" --passwordbox "" 0 0
}

input_dialog() {
    dialog --stdout --title "$1" --inputbox "" 0 0
}

patch_pacman_config() {
    sed -i "s/#Color/Color/g" $1
    sed -i "s/#VerbosePkgLists/VerbosePkgLists/g" $1
    sed -i "s/#ParallelDownloads.*/ParallelDownloads = $(nproc)\nILoveCandy/g" $1
}

#
# DIALOGS
#

disclamer="This script was made by a random Arch Linux user for is own needs, it may not match yours.
This script doesnt give any form of warranty. (GPLv3)

Do you want to continue ?
"

dialog --stdout --title " ! ! ! W A R N I N G ! ! ! " --yesno "$disclamer" 0 0
root_partition=$(select_disk_part_dialog " Root partition ")
efi_partition=$(select_disk_part_dialog " EFI partition ")
grub_disk=$(select_disk_part_dialog " GRUB device ")
disk_password=$(password_dialog " Disk password ")
hostname=$(input_dialog " Hostname ")
root_password=$(password_dialog " Root password ")
user_name=$(input_dialog " User name ")
user_display_name=$(input_dialog " User display name ")
user_password=$(password_dialog " User password ")

clear

#
# PREPARATION
#

timedatectl set-timezone Europe/Paris
timedatectl set-ntp true

mkfs.vfat -F32 $efi_partition
echo -n "$disk_password" | cryptsetup luksFormat $root_partition -
echo -n "$disk_password" | cryptsetup open $root_partition filesystem -
mkfs.btrfs -L "Arch Linux" /dev/mapper/filesystem
mount /dev/mapper/filesystem /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@swap
umount /mnt

mount -o compress=zstd,subvol=@ /dev/mapper/filesystem /mnt
mkdir /mnt/boot /mnt/home /mnt/swap
mount -o compress=zstd,subvol=@home /dev/mapper/filesystem /mnt/home
mount -o compress=zstd,subvol=@swap /dev/mapper/filesystem /mnt/swap
mount $efi_partition /mnt/boot

btrfs filesystem mkswapfile --size $(cat /proc/meminfo | grep MemTotal | awk '{print $2}')K /mnt/swap/swapfile
swapon /mnt/swap/swapfile

#
# INSTALLATION
#

patch_pacman_config /etc/pacman.conf
pacstrap -K /mnt ${pkgs[*]}

#
# SYSTEM CONFIGURATION
#

genfstab -U /mnt > /mnt/etc/fstab
echo "$hostname" > /mnt/etc/hostname
echo "127.0.0.1    localhost" > /mnt/etc/hosts
echo "::1    localhost" >> /mnt/etc/hosts
echo "KEYMAP=fr" > /mnt/etc/vconsole.conf
echo "FONT=ter-v16n" >> /mnt/etc/vconsole.conf
echo "LANG=fr_FR.UTF-8" > /mnt/etc/locale.conf
echo "fr_FR.UTF-8 UTF-8" > /mnt/etc/locale.gen
patch_pacman_config /mnt/etc/pacman.conf

arch-chroot /mnt locale-gen
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
arch-chroot /mnt hwclock --utc --systohc

mkdir -p /mnt/etc/X11/xorg.conf.d
echo "Section \"InputClass\"" > /mnt/etc/X11/xorg.conf.d/00-keyboard.conf
echo "    Identifier \"system-keyboard\"" >> /mnt/etc/X11/xorg.conf.d/00-keyboard.conf
echo "    MatchIsKeyboard \"on\"" >> /mnt/etc/X11/xorg.conf.d/00-keyboard.conf
echo "    Option \"XkbLayout\" \"fr\"" >> /mnt/etc/X11/xorg.conf.d/00-keyboard.conf
echo "    Option \"XkbOptions\" \"caps:escape_shifted_capslock\"" >> /mnt/etc/X11/xorg.conf.d/00-keyboard.conf
echo "EndSection" >> /mnt/etc/X11/xorg.conf.d/00-keyboard.conf

mkdir -p /mnt/etc/sddm.conf.d
echo "[Theme]" > /mnt/etc/sddm.conf.d/kde_settings.conf
echo "Current=breeze" >> /mnt/etc/sddm.conf.d/kde_settings.conf
echo "CursorTheme=breeze_cursors" >> /mnt/etc/sddm.conf.d/kde_settings.conf

arch-chroot /mnt systemctl enable cups.socket firewalld.service fstrim.timer NetworkManager.service paccache.timer sddm.service

#
# USER AND ROOT CONFIGURATION
#

echo -n -e "$root_password\n$root_password" | arch-chroot /mnt passwd root
arch-chroot /mnt useradd -m -g users -G wheel -s /bin/zsh -c "$user_display_name" $user_name
echo -n -e "$user_password\n$user_password" | arch-chroot /mnt passwd $user_name
echo "$user_name ALL=(ALL:ALL) ALL" >> /mnt/etc/sudoers

#
# BOOT CONFIGURATION
#

sed -i "s/MODULES=()/MODULES=(i915)/g" /mnt/etc/mkinitcpio.conf
sed -i "s/HOOKS=(.*)/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems resume fsck)/g" /mnt/etc/mkinitcpio.conf

root_partition_uuid=$(lsblk -lp -o name,uuid | grep $root_partition | awk '{print $2}')
filesystem_uuid=$(lsblk -lp -o name,uuid | grep /dev/mapper/filesystem | awk '{print $2}')
resume_offset=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile)

sed -i "s/GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/g" /mnt/etc/default/grub
sed -i "s/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/g" /mnt/etc/default/grub
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\".*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 cryptdevice=UUID=${root_partition_uuid}:filesystem resume=UUID=${filesystem_uuid} resume_offset=${resume_offset}\"/g" /mnt/etc/default/grub
sed -i "s/GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/g" /mnt/etc/default/grub
sed -i "s/#GRUB_TERMINAL_OUTPUT/GRUB_TERMINAL_OUTPUT/g" /mnt/etc/default/grub
sed -i "s/#GRUB_SAVEDEFAULT/GRUB_SAVEDEFAULT/g" /mnt/etc/default/grub
sed -i "s/#GRUB_DISABLE_SUBMENU/GRUB_DISABLE_SUBMENU/g" /mnt/etc/default/grub

arch-chroot /mnt mkinitcpio -P
arch-chroot /mnt grub-install $grub_disk --efi-directory /boot --bootloader-id "Arch Linux"
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

#
# AUR INSTALLATION
#

sed -i "s/CFLAGS=\"-march=.* -mtune=.* -O2/CFLAGS=\"-march=native -O3/g" /mnt/etc/makepkg.conf
sed -i "s/LDFLAGS=\"-Wl,-O1/LDFLAGS=\"-Wl,-O3/g" /mnt/etc/makepkg.conf
sed -i "s/#RUSTFLAGS=\".*\"/RUSTFLAGS=\"-C opt-level=3 -C target-cpu=native\"/g" /mnt/etc/makepkg.conf
sed -i "s/#MAKEFLAGS=\".*\"/MAKEFLAGS=\"-j$(nproc)\"/g" /mnt/etc/makepkg.conf

arch-chroot /mnt su -c "rustup default stable" $user_name
arch-chroot /mnt su -c "cd /home/$user_name;git clone https://aur.archlinux.org/paru" $user_name
arch-chroot /mnt su -c "cd /home/$user_name/paru;makepkg --noconfirm" $user_name
arch-chroot /mnt pacman --noconfirm -U /home/$user_name/paru/$(ls /mnt/home/$user_name/paru | grep "paru.*\.pkg.tar.zst")
rm -r /mnt/home/$user_name/paru
sed -i "s/#BottomUp/BottomUp/g" /mnt/etc/paru.conf

#
# CLEANING
#

arch-chroot /mnt pacman --noconfirm -Runs ${unpkgs[*]}
arch-chroot /mnt paccache -r -u -k 0

#
# END
#

clear

echo ""
echo "#######################################################################"
echo "#  ___ _   _ ____ _____  _    _     _        _  _____ ___ ___  _   _  #"
echo "# |_ _| \ | / ___|_   _|/ \  | |   | |      / \|_   _|_ _/ _ \| \ | | #"
echo "#  | ||  \| \___ \ | | / _ \ | |   | |     / _ \ | |  | | | | |  \| | #"
echo "#  | || |\  |___) || |/ ___ \| |___| |___ / ___ \| |  | | |_| | |\  | #"
echo "# |___|_| \_|____/ |_/_/   \_\_____|_____/_/   \_\_| |___\___/|_| \_| #"
echo "#                                                                     #"
echo "#         ____ ___  __  __ ____  _     _____ _____ _____ ____         #"
echo "#        / ___/ _ \|  \/  |  _ \| |   | ____|_   _| ____|  _ \        #"
echo "#       | |  | | | | |\/| | |_) | |   |  _|   | | |  _| | | | |       #"
echo "#       | |__| |_| | |  | |  __/| |___| |___  | | | |___| |_| |       #"
echo "#        \____\___/|_|  |_|_|   |_____|_____| |_| |_____|____/        #"
echo "#######################################################################"
echo ""
