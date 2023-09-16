#!/bin/bash

# this module is needed for CRIU to dump socket
modules=(tcp_diag udp_diag raw_diag unix_diag af_packet_diag inet_diag netlink_diag \
ip6_tables ip6table_filter)

for module in ${modules[@]}; do
  modprobe $module
done
