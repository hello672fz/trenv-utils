#!/bin/bash

set -e

rootfs_file=/root/multipass-shared/rootfs
mount_point=/root/qemu_linux/mnt
pkgs_path=/root/multipass-shared/pkgs

function faasd_prepare() {
  echo "prepare faasd..."
  cp /root/go/src/github.com/openfaas/faasd/bin/faasd $mount_point/usr/local/bin
  cp /root/go/bin/faas-cli $mount_point/usr/local/bin

  cp /root/go/src/github.com/openfaas/faasd/resolv.conf $mount_point/root
  cp /root/go/src/github.com/openfaas/faasd/resolv.conf $mount_point/etc/resolv.conf
  
  cp /root/multipass-shared/stack.yml "$mount_point/root"
  mkdir -p "$mount_point/root/template"
  cp -r /root/multipass-shared/faasd-testdriver/functions/template/hybrid-py $mount_point/root/template

  mkdir -p $mount_point/var/lib/faasd/
  cp -r $pkgs_path $mount_point/var/lib/faasd/

  cp /root/qemu_linux/test-faasd.sh $mount_point/root
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
  cp /root/criu/criu/criu $mount_point/root
  cp /lib/x86_64-linux-gnu/libprotobuf-c.so.1 $mount_point/usr/lib
}


function simple_test_prepare() {
  local apps=("h-memory" "h-hello-world")
  for app in ${apps[@]}; do
    mkdir -p $mount_point/root/${app}
    cp /var/lib/faasd/pkgs/${app}/index.py $mount_point/root/${app}/index.py
    cp -r /var/lib/faasd/pkgs/${app}/function $mount_point/root/${app}
  done
  cp /root/qemu_linux/test-criu.sh $mount_point/root
}

function test_driver_prepare() {
  mkdir -p $mount_point/root/faasd-testdriver
  cp /root/multipass-shared/faasd-testdriver/main.py $mount_point/root/faasd-testdriver
  cp /root/multipass-shared/faasd-testdriver/test_driver.py $mount_point/root/faasd-testdriver
  cp /root/multipass-shared/faasd-testdriver/config.yml $mount_point/root/faasd-testdriver
  cp /root/multipass-shared/faasd-testdriver/workload_1.json $mount_point/root/faasd-testdriver
  cp /root/multipass-shared/faasd-testdriver/requirements.txt $mount_point/root/faasd-testdriver
}

# main start:

umount $mount_point || true
mkdir -p $mount_point
mount -o loop $rootfs_file $mount_point

criu_prepare
# simple_test_prepare
container_runtime_prepare
faasd_prepare
test_driver_prepare

cp /root/qemu_linux/insmod.sh $mount_point/root
cp /root/micro_bench/bin/cgo_mount $mount_point/root
cp /root/micro_bench/bin/no_cgo_mount $mount_point/root

umount $mount_point
