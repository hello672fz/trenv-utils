#!/bin/bash

rootfs_file=/root/multipass-shared/rootfs
mount_point=/root/qemu_linux/mnt

umount $mount_point > /dev/null 2>&1
mount -o loop $rootfs_file $mount_point

# app file

apps=("h-memory" "h-hello-world")
for app in ${apps[@]}; do
  mkdir -p $mount_point/root/${app}
  cp /var/lib/faasd/pkgs/${app}/index.py $mount_point/root/${app}/index.py
  cp -r /var/lib/faasd/pkgs/${app}/function $mount_point/root/${app}
done


# binary
cp /root/criu/criu/criu $mount_point/usr/bin
cp -r /root/qemu_linux/insmod.sh $mount_point/root
cp -r /root/qemu_linux/test-criu.sh $mount_point/root

# library
cp /lib/x86_64-linux-gnu/libprotobuf-c.so.1 $mount_point/usr/lib

umount $mount_point
