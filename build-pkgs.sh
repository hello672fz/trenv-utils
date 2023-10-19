#!/bin/bash
set -e

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <Path-to-faasd-build-dir>"
  exit 1
fi

faasd_build_path=$(realpath $1)
workdir=$(dirname "$faasd_build_path")
output_dir=$workdir/pkgs

for p in ${faasd_build_path}/* ;do
  # we only care about dir
  if [ ! -d $p ]; then
    continue
  fi
  lambda=$(basename $p)
  echo "process $lambda ..."

  mkdir -p ${output_dir}/$lambda
  cd $faasd_build_path/$lambda
  docker build --build-arg http_proxy=http://172.17.0.1:7890 \
    --build-arg https_proxy=http://172.17.0.1:7890 \
    --build-arg ADDITIONAL_PACKAGE="iproute2" \
    --target=package --output type=local,dest=${output_dir}/$lambda .
done
