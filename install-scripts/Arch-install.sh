#!/bin/bash

# This script is heavily inspired by https://gist.github.com/Th3Whit3Wolf/0150bd13f4b2667437c55b71bfb073e4
# 0 - SSH
# This isn't necessary but if you ssh into the computer all the other steps are copy and paste
# Set a password for root
#passwd
# Get network access
#iwctl

# """
# # First, if you do not know your wireless device name, list all Wi-Fi devices: 
# [iwd]# device list
# # Then, to scan for networks: 
# [iwd]# station device scan
# # You can then list all available networks: 
# [iwd]# station device get-networks
# # Finally, to connect to a network: 
# [iwd]# station device connect SSID
# """

# Start the ssh daemon
# systemctl start sshd.service

# 1 - Partitioning:
#--------------cfdisk /dev/nvme0n1
# nvme0n1p1 = /boot, nvme0n1p2 = SWAP, nvme0n1p3 = encrypted root
# for the SWAP partition below, try and make it a bit bigger than your RAM, for hybernating
# o , 
# /dev/nvme0n1p1    512M          EFI System
# /dev/nvme0n1p2    (the rest)    Linux Filesystem  

# 2 Encrypt Partition
echo "encrypting root partition"
cryptsetup luksFormat --perf-no_read_workqueue --perf-no_write_workqueue --type luks2 --cipher aes-xts-plain64 --key-size 512 --iter-time 2000 --pbkdf argon2id --hash sha3-512 /dev/nvme0n1p2
cryptsetup --allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent open /dev/nvme0n1p2 cryptroot

# 3 - Formatting the partitions:
# the first one is our ESP partition, so for now we just need to format it
echo "formating EFI and cryptroot"
mkfs.vfat -F32 -n "EFI" /dev/nvme0n1p1
mkfs.btrfs -L Root /dev/mapper/cryptroot

# 4 - Create and Mount Subvolumes
# Create subvolumes for root, home, the package cache, snapshots and the entire Btrfs file system
echo "mounting cryptroot"
mount /dev/mapper/cryptroot /mnt
echo "creating btrfs subvolumes"
btrfs sub create /mnt/@
btrfs sub create /mnt/@home
btrfs sub create /mnt/@paccache
btrfs sub create /mnt/@var_tmp
btrfs sub create /mnt/@var_log
btrfs sub create /mnt/@snapshots
btrfs sub create /mnt/@rw-snapshots
btrfs sub create /mnt/@swap
umount /mnt

# Mount the subvolumes
echo "mounting all subvolumes"
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p -p /mnt/{boot,home,var/cache/pacman/pkg,var/tmp,var/log,.snapshots,.rw-snapshots,.swap}
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@paccache /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@var_tmp /dev/mapper/cryptroot /mnt/var/tmp
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@var_log /dev/mapper/cryptroot /mnt/var/log
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@rw-snapshots /dev/mapper/cryptroot  /mnt/.rw-snapshots
mount -o noatime,nodiratime,compress=no,space_cache=v2,ssd,subvol=@swap /dev/mapper/cryptroot /mnt/.swap


# Create Swapfile
echo "creating swapfile"
truncate -s 0 /mnt/.swap/swapfile
chattr +C /mnt/.swap/swapfile
btrfs property set /mnt/.swap/swapfile compression none
fallocate -l 20G /mnt/.swap/swapfile
chmod 600 /mnt/.swap/swapfile
mkswap /mnt/.swap/swapfile
swapon /mnt/.swap/swapfile

# Mount the EFI partition
echo "mounting /boot"
mount /dev/nvme0n1p1 /mnt/boot

# 5 Base System and /etc/fstab
echo "creating new mirrorlist"
reflector -c "DE" -f 12 -l 10 -n 12 --save /etc/pacman.d/mirrorlist


# The following assumes you have an AMD CPU & GPU
echo "running pacstrap"
pacstrap /mnt base base-devel linux linux-headers linux-firmware amd-ucode btrfs-progs sbsigntools \
    nano zstd networkmanager mesa vulkan-radeon libva-mesa-driver mesa-vdpau \
    xf86-video-amdgpu openssh refind zsh zsh-completions acpi efibootmgr kompare \
    zsh-autosuggestions zsh-history-substring-search zsh-syntax-highlighting git \
    pigz pbzip2 reflector plasma-meta kde-system-meta yakuake kate ark filelight kfind konsole kdf \
    kdeconnect krusader ktorrent kmail dolphin-plugins gwenview kaddressbook korganizer \
    krunner ksnip digikam firefox firefox-i18n-de fwupd gamemode gimp lsd man-db man-pages \
    man-pages-de cantata mpd gst-plugin-pipewire pipewire-alsa pipewire-pulse snapper \
    profile-sync-daemon kdialog solaar signal-desktop mumble teamspeak3 lutirs \
    prusa-slicer ksysguard libreoffice-fresh libreoffice-fresh-de aspell-de aspell-en \
    flatpak flatpak-xdg-utils ttf-dejavu ttf-nerd-fonts-symbols neochat pkgstats cups cups-filters cups-pdf cups-pk-helper \
    print-manager system-config-printer powerline-fonts kdepim-addons okular bogofilter \
    iotop neovim neovim-qt realtime-privileges noto-fonts-emoji hunspell hunspell-de hunspell-en_us \
    plasma-wayland-session plasma-wayland-protocols 

# generate the fstab
echo "generating fstab"
genfstab -U /mnt > /mnt/etc/fstab

# 6 System Configuration
# Use timedatectl(1) to ensure the system clock is accurate
timedatectl set-ntp true
# Copy mirrorlist created earlier to new install
echo "copying mirrorlist to /mnt"
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
# chroot into the new system
echo "chrooting into new install"
echo "run /Arch-install-chroot.sh in chroot"
cp "$(dirname $(realpath $0))/Arch-install-chroot.sh" /mnt/Arch-install-chroot.sh
# inserting the correct UUID for the refind.conf
sed -i 's/=UUID=/='$(blkid /dev/nvme0n1p2 | cut -d " " -f2 | cut -d '=' -f2 | sed 's/\"//g')'=/g' /mnt/Arch-install-chroot.sh
arch-chroot /mnt

# 11 - reboot into your new install
echo "Finished - now we can reboot with:
        umount -R /mnt
        swapoff -a
        reboot"
read -p "Do you want to reboot now? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
else
    umount -R /mnt
    swapoff -a
    reboot
fi 

# 12 - After instalation
#systemctl enable --now NetworkManager
# systemctl enable --now sshd
#sudo pacman -S snapper sddm
#sudo umount /.snapshots
#sudo rm -r /.snapshots
#sudo snapper -c root create-config /
#sudo mount -a
#sudo chmod 750 -R /.snapshots 
