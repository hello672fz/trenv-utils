#!/bin/bash
set -e

MOUNT_POINT=/root/qemu_linux/mnt
OUTPUT_DIR=/root/result/baseline

if [ -d $OUTPUT_DIR ]; then
  echo "there is already a dir at $OUTPUT_DIR, please remove it first"
  exit 1
fi

mkdir -p $MOUNT_POINT
mkdir -p $OUTPUT_DIR

umount $MOUNT_POINT || true
mount -o loop /root/multipass-shared/rootfs  $MOUNT_POINT
cp $MOUNT_POINT/root/faasd-testdriver/*.png $OUTPUT_DIR

cp $MOUNT_POINT/root/faasd.log $OUTPUT_DIR
cp $MOUNT_POINT/root/test.log $OUTPUT_DIR
cp $MOUNT_POINT/root/metrics.output $OUTPUT_DIR
cp $MOUNT_POINT/root/mpstat.output $OUTPUT_DIR

