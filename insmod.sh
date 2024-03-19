#!/bin/bash

echo "insert needed kernel module..."
# this module is needed for CRIU to dump socket
modules=(tcp_diag udp_diag raw_diag unix_diag af_packet_diag inet_diag netlink_diag \
ip6_tables ip6table_filter)

for module in ${modules[@]}; do
  modprobe $module
done

# this module is needed for container and criu working with container
container_modules=(overlay llc stp bridge xt_mark xt_comment xt_MASQUERADE \
  xt_conntrack nf_conntrack nf_conntrack_netlink)
for mod in ${container_modules[@]}; do
  modprobe $mod
done

modprobe rdma_rxe
