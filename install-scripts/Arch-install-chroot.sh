#!/bin/bash

# Replace username with the name for your new user
export USER=termy
# Replace hostname with the name for your host
export HOST=Wunderland
# Replace Europe/London with your Region/City
export TZ="Europe/Berlin"
# - set root password
echo "set password for root"
passwd

# - set locale
echo "generating locale"
echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
echo "de_DE ISO-8859-1"  >> /etc/locale.gen
echo "de_DE@euro ISO-8859-15" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8"  >> /etc/locale.gen # this is needed for steam
locale-gen
echo "setting locale and keymap"
echo "LANG=\"de_DE.UTF-8\"" > /etc/locale.conf
echo "KEYMAP=de-latin1" > /etc/vconsole.conf
echo "FONT=lat9w-16" >> /etc/vconsole.conf
export LANG="de_DE.UTF-8"

# - set timezone
echo "setting timezone"
ln -sf /usr/share/zoneinfo/$TZ /etc/localtime
hwclock --systohc --utc # or hwclock --systohc --utc

# - set hostname
echo "setting hostname"
echo $HOST > /etc/hostname

# - add user 
echo "adding new user"
useradd -mg users -G wheel,input,lp,storage,video,sys,network,power,realtime -s /bin/zsh $USER
passwd $USER
echo "$USER ALL=(ALL) ALL" >> /etc/sudoers 
# echo "Defaults timestamp_timeout=0" >> /etc/sudoers

# - set hosts
echo "creating hosts-file"
cat << EOF >> /etc/hosts
echo "# <ip-address>	<hostname.domain.org>	<hostname>"
echo "127.0.0.1	localhost"
echo "::1		localhost"
echo "127.0.1.1	$HOST.localdomain	$HOST" 
EOF
# - Set Network Manager iwd backend
#echo "[device]" > /etc/NetworkManager/conf.d/nm.conf
#echo "wifi.backend=iwd" >> /etc/NetworkManager/conf.d/nm.conf

# - Preventing snapshot slowdowns
echo 'PRUNENAMES = ".snapshots"' >> /etc/updatedb.conf

# 6 - fix the mkinitcpio.conf to contain what we actually need.
# sed -i 's/BINARIES=()/BINARIES=("\/usr\/bin\/btrfs")/' /etc/mkinitcpio.conf
# If using amdgpu and would like earlykms
echo "modifying mkinitcpio.conf"
sed -i 's/^MODULES=().*/MODULES=()/' /etc/mkinitcpio.conf
sed -i 's/^#COMPRESSION="zstd".*/COMPRESSION="zstd"/' /etc/mkinitcpio.conf
#sed -i 's/#COMPRESSION_OPTIONS=()/COMPRESSION_OPTIONS=(-9)/' mkinitcpio.conf
# if you have more than 1 btrfs drive
sed -i 's/^HOOKS.*/HOOKS=(base systemd sd-vconsole autodetect modconf block keyboard sd-encrypt filesystems )/' /etc/mkinitcpio.conf
# else
# sed -i 's/^HOOKS/HOOKS=(base systemd autodetect modconf block sd-encrypt resume filesystems keyboard fsck)/' mkinitcpio.conf

echo "running mkinitcpio"
mkinitcpio -p linux

# 10 Bootloader
#su $USER
#cd ~
#git clone https://aur.archlinux.org/yay.git && cd yay
#makepkg -si
#cd .. && sudo rm -dR yay
#yay -S shim-signed pamac-aur

# If you use a bare git to store dotfiles install them now
# git clone --bare https://github.com/user/repo.git $HOME/.repo
#exit

echo "installing refind"
refind-install
#refind-install --shim /usr/share/shim-signed/shimx64.efi --localkeys
#sbsign --key /etc/refind.d/keys/refind_local.key --cert /etc/refind.d/keys/refind_local.crt --output /boot/vmlinuz-linux /boot/vmlinuz-linux

echo "creating some pacman hooks"
mkdir -p /etc/pacman.d/hooks

# cat << EOF > /etc/pacman.d/hooks/999-sign_kernel_for_secureboot.hook
# """
# [Trigger]
# Operation = Install
# Operation = Upgrade
# Type = Package
# Target = linux
# Target = linux-lts
# Target = linux-hardened
# Target = linux-zen
# [Action]
# Description = Signing kernel with Machine Owner Key for Secure Boot
# When = PostTransaction
# Exec = /usr/bin/find /boot/ -maxdepth 1 -name 'vmlinuz-*' -exec /usr/bin/sh -c '/usr/bin/sbsign --key /etc/refind.d/keys/refind_local.key --cert /etc/refind.d/keys/refind_local.crt --output {} {}'
# Depends = sbsigntools
# Depends = findutils
# Depends = grep
# EOF

cat << EOF > /etc/pacman.d/hooks/refind.hook
[Trigger]
Operation=Upgrade
Type=Package
Target=refind
[Action]
Description = Updating rEFInd on ESP
When=PostTransaction
Exec=/usr/bin/refind-install
EOF

cat << EOF > /etc/pacman.d/hooks/zsh.hook
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Path
Target = usr/bin/*
[Action]
Depends = zsh
When = PostTransaction
Exec = /usr/bin/install -Dm644 /dev/null /var/cache/zsh/pacman
EOF

cat << EOF > /etc/pacman.d/hooks/mirrorupgrade.hook
[Trigger]
Operation = Upgrade
Type = Package
Target = pacman-mirrorlist

[Action]
Description = Updating pacman-mirrorlist with reflector and removing pacnew...
When = PostTransaction
Depends = reflector
Exec = /bin/sh -c 'systemctl start reflector.service; if [ -f /etc/pacman.d/mirrorlist.pacnew ]; then rm /etc/pacman.d/mirrorlist.pacnew; fi'
EOF

echo "setting schedulers for nvme, ssd and hdd"
mkdir -p /etc/udev/rules.d
cat << EOF > /etc/udev/rules.d/60-ioschedulers.rules
# set scheduler for NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
# set scheduler for SSD and eMMC
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# set scheduler for rotating disks
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF

echo "creating reflector.conf"
mkdir -p /etc/xdg/reflector
cat << EOF > /etc/xdg/reflector/reflector.conf
# Set the output path where the mirrorlist will be saved (--save).
--save /etc/pacman.d/mirrorlist
# Select the transfer protocol (--protocol).
--protocol https
# Use only the  most recently synchronized mirrors (--latest).
--latest 100
# Sort the mirrors by MirrorStatus score
--sort score
EOF


# autologin with SDDM
echo "creating sddm autologin .conf"
mkdir -p /etc/sddm.conf.d
cat << EOF > /etc/sddm.conf.d/kde_settings.conf
[Autologin]
Relogin=false
Session=plasma
User=$USER

[General]
HaltCommand=/usr/bin/systemctl poweroff
Numlock=on
RebootCommand=/usr/bin/systemctl reboot

[Theme]
Current=breeze
CursorTheme=breeze_cursors
Font=Noto Sans,10,-1,5,50,0,0,0,0,0

[Users]
MaximumUid=60000
MinimumUid=1000
EOF

# this will help declutter the home directory from zsh-dotfiles
mkdir -p /etc/zsh
echo 'export ZDOTDIR=$HOME/.config/zsh' >  /etc/zsh/zshenv
echo 'export HISTFILE=$XDG_DATA_HOME/zsh/history' >>  /etc/zsh/zshenv


echo "creating sysctl tweaks"
mkdir -p /etc/sysctl.d
cat << EOF >/etc/sysctl.d/99-sysctl-performance-tweaks.conf
# The swappiness sysctl parameter represents the kernel's preference (or avoidance) of swap space. Swappiness can have a value between 0 and 100, the default value is 60. 
# A low value causes the kernel to avoid swapping, a higher value causes the kernel to try to use swap space. Using a low value on sufficient memory is known to improve responsiveness on many systems.
vm.swappiness=10

# The value controls the tendency of the kernel to reclaim the memory which is used for caching of directory and inode objects (VFS cache). 
# Lowering it from the default value of 100 makes the kernel less inclined to reclaim VFS cache (do not set it to 0, this may produce out-of-memory conditions)
vm.vfs_cache_pressure=50

# This action will speed up your boot and shutdown, because one less module is loaded. Additionally disabling watchdog timers increases performance and lowers power consumption
# Disable NMI watchdog
#kernel.nmi_watchdog = 0

# Contains, as a percentage of total available memory that contains free pages and reclaimable
# pages, the number of pages at which a process which is generating disk writes will itself start
# writing out dirty data (Default is 20).
vm.dirty_ratio = 5

# Contains, as a percentage of total available memory that contains free pages and reclaimable
# pages, the number of pages at which the background kernel flusher threads will start writing out
# dirty data (Default is 10).
vm.dirty_background_ratio = 5

# This tunable is used to define when dirty data is old enough to be eligible for writeout by the
# kernel flusher threads.  It is expressed in 100'ths of a second.  Data which has been dirty
# in-memory for longer than this interval will be written out next time a flusher thread wakes up
# (Default is 3000).
#vm.dirty_expire_centisecs = 3000

# The kernel flusher threads will periodically wake up and write old data out to disk.  This
# tunable expresses the interval between those wakeups, in 100'ths of a second (Default is 500).
vm.dirty_writeback_centisecs = 1500

# Enable the sysctl setting kernel.unprivileged_userns_clone to allow normal users to run unprivileged containers.
kernel.unprivileged_userns_clone=1

# To hide any kernel messages from the console
kernel.printk = 3 3 3 3

# Restricting access to kernel logs
kernel.dmesg_restrict = 1

# Restricting access to kernel pointers in the proc filesystem
kernel.kptr_restrict = 2

# Disable Kexec, which allows replacing the current running kernel. 
kernel.kexec_load_disabled = 1

# Increasing the size of the receive queue.
# The received frames will be stored in this queue after taking them from the ring buffer on the network card.
# Increasing this value for high speed cards may help prevent losing packets: 
net.core.netdev_max_backlog = 16384

# Increase the maximum connections
#The upper limit on how many connections the kernel will accept (default 128): 
net.core.somaxconn = 8192

# Increase the memory dedicated to the network interfaces
# The default the Linux network stack is not configured for high speed large file transfer across WAN links (i.e. handle more network packets) and setting the correct values may save memory resources: 
net.core.rmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_default = 1048576
net.core.wmem_max = 16777216
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 1048576 2097152
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# Enable TCP Fast Open
# TCP Fast Open is an extension to the transmission control protocol (TCP) that helps reduce network latency
# by enabling data to be exchanged during the sender’s initial TCP SYN [3]. 
# Using the value 3 instead of the default 1 allows TCP Fast Open for both incoming and outgoing connections: 
net.ipv4.tcp_fastopen = 3

# Enable BBR
# The BBR congestion control algorithm can help achieve higher bandwidths and lower latencies for internet traffic
net.core.default_qdisc = cake
net.ipv4.tcp_congestion_control = bbr

# TCP SYN cookie protection
# Helps protect against SYN flood attacks. Only kicks in when net.ipv4.tcp_max_syn_backlog is reached: 
net.ipv4.tcp_syncookies = 1

# Protect against tcp time-wait assassination hazards, drop RST packets for sockets in the time-wait state. Not widely supported outside of Linux, but conforms to RFC: 
net.ipv4.tcp_rfc1337 = 1

# By enabling reverse path filtering, the kernel will do source validation of the packets received from all the interfaces on the machine. This can protect from attackers that are using IP spoofing methods to do harm. 
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# To use the new FQ-PIE Queue Discipline (>= Linux 5.6) in systems with systemd (>= 217), will need to replace the default fq_codel. 
net.core.default_qdisc = fq_pie
EOF

# Optimize Makepkg
echo "optimizing makepkg.conf"
cp /etc/makepkg.conf /etc/makepkg.conf.bak
sed -i 's/^CFLAGS=.*/CFLAGS="-march=native -mtune=native -O2 -pipe -fstack-protector-strong --param=ssp-buffer-size=4 -fno-plt /' /etc/makepkg.conf
sed -i 's/^CXXFLAGS=.*/CXXFLAGS="${CFLAGS}"/' /etc/makepkg.conf
sed -i 's/^#RUSTFLAGS=.*/RUSTFLAGS="-C opt-level=2 -C target-cpu=native"/' /etc/makepkg.conf
sed -i 's/^#BUILDDIR=.*/BUILDDIR=\/tmp\/makepkg /' /etc/makepkg.conf
sed -i 's/^#MAKEFLAGS=.*/MAKEFLAGS="-j$(getconf _NPROCESSORS_ONLN) --quiet"/' /etc/makepkg.conf
sed -i 's/^COMPRESSGZ=.*/COMPRESSGZ=(pigz -c -f -n)/' /etc/makepkg.conf
sed -i 's/^COMPRESSBZ2=.*/COMPRESSBZ2=(pbzip2 -c -f)/' /etc/makepkg.conf
sed -i 's/^COMPRESSXZ=.*/COMPRESSXZ=(xz -T "$(getconf _NPROCESSORS_ONLN)" -c -z --best -)/' /etc/makepkg.conf
sed -i 's/^COMPRESSZST=.*/COMPRESSZST=(zstd -c -z -q --ultra -T0 -22 -)/' /etc/makepkg.conf
sed -i 's/^COMPRESSLZ=.*/COMPRESSLZ=(lzip -c -f)/' /etc/makepkg.conf
sed -i 's/^COMPRESSLRZ=.*/COMPRESSLRZ=(lrzip -9 -q)/' /etc/makepkg.conf
sed -i 's/^COMPRESSLZO=.*/COMPRESSLZO=(lzop -q --best)/' /etc/makepkg.conf
sed -i 's/^COMPRESSZ=.*/COMPRESSZ=(compress -c -f)/' /etc/makepkg.conf
sed -i 's/^COMPRESSLZ4=.*/COMPRESSLZ4=(lz4 -q --best)/' /etc/makepkg.conf

# Misc options
cp /etc/pacman.conf /etc/pacman.conf.bak
sed -i 's/^#UseSyslog.*/UseSyslog/' /etc/pacman.conf
sed -i 's/^#Color.*/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
sed -i 's/^#CheckSpace.*/CheckSpace/' /etc/pacman.conf

# mkdir -p /boot/EFI/refind/themes
# git clone https://github.com/dheishman/refind-dreary.git /boot/EFI/refind/themes/refind-dreary
# mv  /boot/EFI/refind/themes/refind-dreary/highres /boot/EFI/refind/themes/refind-dreary-tmp
# rm -dR /boot/EFI/refind/themes/refind-dreary
# mv /boot/EFI/refind/themes/refind-dreary-tmp /boot/EFI/refind/themes/refind-dreary

# Replace 2560 1440 with your monitors resolution
cp /boot/EFI/refind/refind.conf /boot/EFI/refind/refind.conf.bak
sed -i 's/^#resolution 3.*/resolution 2560 1440/' /boot/EFI/refind/refind.conf
sed -i 's/^#use_graphics_for osx,linux.*/use_graphics_for linux/' /boot/EFI/refind/refind.conf
sed -i 's/^#scanfor internal,external,optical,manual.*/scanfor manual,external/' /boot/EFI/refind/refind.conf

# add the UUID to the options (example below)
echo "creating refind stanza"
cat << EOF >> /boot/EFI/refind/refind.conf
menuentry "Arch Linux" {
    icon     /EFI/refind/themes/refind-dreary/icons/os_arch.png
    volume   "Arch Linux"
    loader   /vmlinuz-linux
    initrd   /initramfs-linux.img
    options  "rd.luks.name=UUID=cryptroot rd.luks.options=allow-discards,no-read-workqueue,no-write-workqueue root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet splash zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=20 zswap.zpool=z3fold amdgpu.ppfeaturemask=0xffffffff nmi_watchdog=0 initrd=/amd-ucode.img"
    submenuentry "Boot using fallback initramfs" {
        initrd /boot/initramfs-linux-fallback.img
    }
}
EOF

# enable some systemd units
systemctl enable sddm.service
systemctl enable NetworkManager.service
systemctl enable bluetooth.service
systemctl enable cronie.service
systemctl enable cups.socket
systemctl enable pkgfile-update.timer
systemctl enable fstrim.timer


echo "edit /boot/EFI/refind/refind.conf and insert correct UUID"

# Laptop Battery Life Improvements
#echo "vm.dirty_writeback_centisecs = 6000" > /etc/sysctl.d/dirty.conf
#echo "load-module module-suspend-on-idle" >> /etc/pulse/default.pa
#if [ $(( $(lspci -k | grep snd_ac97_codec | wc -l) + 1 )) -gt 1 ]; then echo "options snd_ac97_codec power_save=1" > /etc/modprobe.d/audio_powersave.conf; fi
#if [ $(( $(lspci -k | grep snd_hda_intel | wc -l) + 1 )) -gt 1 ]; then echo "options snd_hda_intel power_save=1" > /etc/modprobe.d/audio_powersave.conf; fi
#if [ $(lsmod | grep '^iwl.vm' | awk '{print $1}') == "iwlmvm" ]; then echo "options iwlwifi power_save=1" > /etc/modprobe.d/iwlwifi.conf; echo "options iwlmvm power_scheme=3" >> /etc/modprobe.d/iwlwifi.conf; fi
#if [ $(lsmod | grep '^iwl.vm' | awk '{print $1}') == "iwldvm" ]; then echo "options iwldvm force_cam=0" >> /etc/modprobe.d/iwlwifi.conf; fi
#echo 'ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", ATTR{link_power_management_policy}="med_power_with_dipm"' > /etc/udev/rules.d/hd_power_save.rules

#exit chroot
exit 1


