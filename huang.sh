#!/bin/sh
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

. /usr/share/initramfs-tools/hook-functions
# Begin real processing below this line

# used to configure dax device
copy_file blob /root/linux/vmlinux /boot/vmlinux-6.1.0-rc8+

for file in /root/kselftest/pseudo_mm/*; do
  echo "copying kselftest file $(basename $file)"
  copy_exec $file
done

# copy_modules_dir kernel/net/netlink
# copy_modules_dir kernel/net/netfilter
# copy_modules_dir kernel/net/bridge
# copy_modules_dir kernel/net/bridge
copy_modules_dir kernel/net/ipv4
manual_add_modules veth
manual_add_modules af_packet_diag
manual_add_modules unix_diag
manual_add_modules netlink_diag

manual_add_modules ip6_tables
manual_add_modules ip6table_filter


exit 0
