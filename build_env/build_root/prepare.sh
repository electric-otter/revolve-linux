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
