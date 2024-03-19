#!/bin/sh
#
# This was used by initramfs-tools (ubuntu 22.04 has this tools)
# to generate initramfs, which can be used by qemu.
#
# If want to test pseudo_mm and the kernel features in qemu, this
# scripts might be helpful.
#
# Copy it into /etc/initramfs-tools/hooks/ and it will worked when
# running:
# mkinitramfs -o ~/initramfs-6.1.0 6.1.0-rc8+
#
# And in qemu command args, specify -initrd ~/initramfs-6.1.0

PREREQ=""
prereqs()
{
     echo "$PREREQ"
}

case $1 in
prereqs)
     prereqs
     exit 0
     ;;
esac

copy_dir()
{
  local dir=$1
  local dst=$2
  for file in $dir/*; do
    local name=$(basename $file)
    if [ -f $file ]; then
      # echo "copying file $file to ${dst}/${name}"
      copy_file blob $file ${dst}/${name}
    fi
    if [ -d $file ]; then
      copy_dir $file ${dst}/${name}
    fi
  done
}

. /usr/share/initramfs-tools/hook-functions
# Begin real processing below this line

# used to configure dax device
#copy_file blob /root/linux/vmlinux /boot/vmlinux-6.1.0-rc8+
#
for file in /root/kselftest/pseudo_mm/*; do
  echo "copying kselftest file $(basename $file)"
  copy_exec $file
done
#
copy_exec /usr/bin/ndctl
#copy_exec /usr/local/bin/crash
#copy_exec /usr/bin/screen
#copy_exec /usr/bin/strings
copy_exec /mnt/data/pseudo-mm-rdma-server/pseudo-mm-rdma-server /root/pseudo-mm-rdma-server
copy_exec /usr/bin/rdma
copy_exec /usr/bin/bash
copy_exec /usr/sbin/lsmod
copy_exec /usr/bin/ping
copy_file blob /root/qemu_linux/insmod.sh /root/insmod.sh

copy_dir /mnt/data/downloads/rdma-core/build /mnt/data/downloads/rdma-core/build 
for file in /mnt/data/downloads/perftest-files/bin/*; do 
  copy_exec $file
done

#copy_file blob /lib/terminfo/l/linux /lib/terminfo/l/linux
#
manual_add_modules pseudo_mm_rdma
manual_add_modules rdma_rxe
manual_add_modules rdma_ucm

copy_modules_dir kernel/net/ipv4
manual_add_modules veth
manual_add_modules af_packet_diag
manual_add_modules unix_diag
manual_add_modules netlink_diag

manual_add_modules ip6_tables
manual_add_modules ip6table_filter

manual_add_modules xt_comment
manual_add_modules xt_mark
manual_add_modules xt_MASQUERADE
manual_add_modules xt_conntrack
manual_add_modules nf_conntrack_netlink



exit 0
