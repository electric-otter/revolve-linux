#!/bin/bash
set -e

# Ensure the user 'revolve-linux' exists
if ! id -u revolve-linux >/dev/null 2>&1; then
    # Create group manually
    echo "revolve-linux:x:1000:" >> /etc/group

    # Create passwd entry manually
    echo "revolve-linux:x:1000:1000::/home/revolve-linux:/bin/bash" >> /etc/passwd

    # Create shadow entry (no password)
    echo "revolve-linux::$(date +%s | awk '{print int($1 / 86400)}'):0:99999:7:::" >> /etc/shadow

    # Create home directory
    mkdir -p /home/revolve-linux
    chown 1000:1000 /home/revolve-linux
    chmod 755 /home/revolve-linux
    wget https://curl.se/download/curl-8.13.0.tar.xz
    tar -xf curl-8.13.0.tar.xz
    cd curl-8.13.0
    ./configure --prefix=/usr
    make
    make install

    # Install Nix PKG manager
    curl -L https://nixos.org/nix/install
fi

# Build directory
mkdir -v build
cd build

# Configure and build toolchain
../configure --prefix=$LFS/tools \
             --with-sysroot=$LFS \
             --target=$LFS_TGT \
             --disable-nls \
             --enable-gprofng=yes \
             --disable-werror \
             --enable-new-dtags \
             --enable-default-hash-style=gnu

make
make install
cd ..

# Openbox install script
cd openbox
chmod +x install-sh
cd ..

# Kernel headers
cd build
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr
cd ..

# Set ownership
chown --from lfs -R root:root $LFS/{usr,lib,var,etc,bin,sbin,tools}
[ "$(uname -m)" = "x86_64" ] && chown --from lfs -R root:root $LFS/lib64

# Build and install Bison
./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
make
make install

# Run tests
./configure --prefix=/usr
make
make check
make install

# Test as tester user (must exist!)
./configure --prefix=/usr
make
chown -R tester .
su tester -c "PATH=$PATH make check"
make install

# Systemd tweaks for network delay
systemctl disable systemd-networkd-wait-online
ln -sf /dev/null /etc/systemd/network/99-default.link
systemctl enable systemd-networkd-wait-online

# /etc/fstab setup
cat > /etc/fstab << "EOF"
# Begin /etc/fstab

# file system  mount-point  type     options             dump  fsck
#                                                              order

/dev/<xxx>     /            <fff>    defaults            1     1
/dev/<yyy>     swap         swap     pri=1               0     0

# End /etc/fstab
EOF

# Kernel config
make mrproper
make menuconfig

# Build and install SDDM
cd sddm
make
make install
cd ..

# Clone and build X Server
git clone https://gitlab.freedesktop.org/xorg/xserver.git
cd xserver
./autogen.sh
make
make install

# Create Initramfs (Minimal BusyBox Example)
mkdir -p $LFS/initramfs/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin}
cp $LFS/tools/bin/busybox $LFS/initramfs/bin/
ln -s bin/busybox $LFS/initramfs/bin/sh
# Add any necessary configurations like /etc/inittab or init script

# Kernel headers
make mrproper
make headers
cp -rv usr/include $LFS/usr/include

# Install GRUB for ISO boot
mkdir -p $LFS/boot/grub
cat > $LFS/boot/grub/grub.cfg << "EOF"
set timeout=5
set default=0

menuentry "Revolve Linux" {
    linux /boot/vmlinuz root=/dev/sr0
    initrd /boot/initramfs.img
}
EOF

# Create the GRUB bootable ISO
grub-mkrescue -o revolve-linux.iso $LFS --modules="normal iso9660 biosdisk memdisk search tar ls"

# Build the ISO using xorriso (optional, if you prefer)
# xorriso -as mkisofs \
#   -iso-level 3 \
#   -full-iso9660-filenames \
#   -volid "REVOLVE_LINUX" \
#   -output revolve-linux.iso \
#   -eltorito-boot boot/grub/i386-pc/eltorito.img \
#   -no-emul-boot -boot-load-size 4 -boot-info-table \
#   $LFS
