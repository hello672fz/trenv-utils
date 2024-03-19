#!/bin/bash

set -e

rootfs_file=/mnt/data/qemu-rootfs/output/rootfs
mount_point=/root/qemu_linux/mnt
pkgs_path=/root/multipass-shared/pkgs

function faasd_prepare() {
  echo "prepare faasd..."
  mkdir -p $mount_point/root/test

  # binary
  cp /root/go/src/github.com/openfaas/faasd/bin/faasd $mount_point/usr/local/bin
  cp /root/go/bin/faas-cli $mount_point/usr/local/bin

  cp /root/go/src/github.com/openfaas/faasd/resolv.conf $mount_point/root
  cp /root/go/src/github.com/openfaas/faasd/resolv.conf $mount_point/etc/resolv.conf
  
  cp /root/qemu_linux/stack.yml $mount_point/root/test
  mkdir -p $mount_point/root/test/template
  cp -r /root/multipass-shared/faasd-testdriver/functions/template/hybrid-py $mount_point/root/test/template
  cp -r /root/multipass-shared/faasd-testdriver/functions/template/hybrid-node18 $mount_point/root/test/template

  mkdir -p $mount_point/var/lib/faasd/
  cp -r $pkgs_path $mount_point/var/lib/faasd/

  cp /root/qemu_linux/test.sh $mount_point/root
  cp /root/qemu_linux/machine-prepare.sh $mount_point/root
  cp /root/qemu_linux/test-common.sh $mount_point/root

  # coping golang dlv for debugging
  cp /root/go/bin/dlv $mount_point/usr/local/bin
}

function container_runtime_prepare() {
  echo "prepare container runtime..."
  local containerd_binaries=(containerd ctr containerd-shim-runc-v2)
  for bin in ${containerd_binaries[@]}; do
    cp /usr/local/bin/${bin} $mount_point/usr/bin
  done
  cp /usr/local/sbin/runc $mount_point/usr/bin

  # copy cni configs and plugin
  mkdir -p $mount_point/etc/cni
  cp -r /etc/cni/net.d/ $mount_point/etc/cni
  mkdir -p $mount_point/opt/cni/bin
  cp /opt/cni/bin/* $mount_point/opt/cni/bin/
}


function criu_prepare() {
  echo "prepare criu..."
  mkdir -p $mount_point/root/downloads
  cp /root/downloads/raw-criu $mount_point/root/downloads/raw-criu
  cp /root/criu/criu/criu $mount_point/root/downloads/switch-criu
  cp /lib/x86_64-linux-gnu/libprotobuf-c.so.1 $mount_point/usr/lib
}


function test_driver_prepare() {
  mkdir -p $mount_point/root/test/faasd-testdriver
  cp /root/multipass-shared/faasd-testdriver/main.py $mount_point/root/test/faasd-testdriver
  cp /root/multipass-shared/faasd-testdriver/test_driver.py $mount_point/root/test/faasd-testdriver
  cp /root/multipass-shared/faasd-testdriver/config.yml $mount_point/root/test/faasd-testdriver
  cp /root/multipass-shared/faasd-testdriver/warmup.json $mount_point/root/test/faasd-testdriver
  cp /root/multipass-shared/faasd-testdriver/workload.json $mount_point/root/test/faasd-testdriver
  cp /root/multipass-shared/faasd-testdriver/requirements.txt $mount_point/root/test/faasd-testdriver
}

# main start:

umount $mount_point || true
mkdir -p $mount_point
mount -o loop $rootfs_file $mount_point

criu_prepare
container_runtime_prepare
faasd_prepare
test_driver_prepare

cp /mnt/data/pseudo-mm-rdma-server/pseudo-mm-rdma-server $mount_point/root/test
cp /mnt/data/pseudo-mm-rdma-server/pseudo-mm-rdma-server.cpp $mount_point/root/test
cp /mnt/data/pseudo-mm-rdma-server/pseudo-mm-rdma-server.h $mount_point/root/test
cp /mnt/data/pseudo-mm-rdma-server/scm.cpp $mount_point/root/test
cp /mnt/data/pseudo-mm-rdma-server/scm.h $mount_point/root/test
cp /root/qemu_linux/insmod.sh $mount_point/root
cp /root/micro_bench/bin/cgo_mount $mount_point/root
cp /root/micro_bench/bin/no_cgo_mount $mount_point/root

umount $mount_point
