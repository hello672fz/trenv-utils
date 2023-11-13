#!/bin/bash

WORKDIR=/root/test
TEMPDIR=/run

test_class=$1
output_dir=/root/test/result/$test_class

echo "copying result to $output_dir"

mkdir -p $output_dir
mv $TEMPDIR/metrics.output $output_dir
mv $TEMPDIR/memory_stat.output $output_dir
mv $TEMPDIR/mpstat.output $output_dir
mv $TEMPDIR/faasd.log $output_dir
mv $TEMPDIR/test.log $output_dir
cp $TEMPDIR/containerd.log $output_dir
cp $WORKDIR/faasd-testdriver/workload.json $output_dir
cp $WORKDIR/faasd-testdriver/gen_trace.py $output_dir
cp /root/go/src/github.com/openfaas/faasd/pkg/constants.go $output_dir
