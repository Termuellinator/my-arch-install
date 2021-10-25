#!/bin/bash

cryptsetup --allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent open /dev/nvme0n1p2 cryptroot

# Mount the subvolumes
echo "mounting all subvolumes"
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@ /dev/mapper/cryptroot /mnt
#mkdir -p -p /mnt/{boot,home,var/cache/pacman/pkg,var/tmp,var/log,.snapshots,.swap}
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@paccache /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@var_tmp /dev/mapper/cryptroot /mnt/var/tmp
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@var_log /dev/mapper/cryptroot /mnt/var/log
mount -o noatime,nodiratime,compress=zstd,commit=60,space_cache=v2,ssd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount -o noatime,nodiratime,compress=no,space_cache=v2,ssd,subvol=@swap /dev/mapper/cryptroot /mnt/.swap


# Mount the EFI partition
echo "mounting /boot"
mount /dev/nvme0n1p1 /mnt/boot


arch-chroot /mnt

