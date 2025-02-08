#!/bin/bash
set -e

DIR=`dirname "${THIS}"`
. "$DIR/test-common.sh"

function download_ctr_images() {
  local apps=(h-hello-world)
  for app in ${apps[@]}; do
    local img_name=docker.io/jialianghuang/${app}:latest
    local output=$(ctr -n openfaas-fn image check "name==${img_name}")
    if [ -z "${output}" ]; then
      # do not found image in containerd
      echo "start pull docker image for $app ..."
      https_proxy=http://192.168.1.126:7890 http_proxy=http://192.168.1.126:7890 ctr image pull $img_name
    fi
  done
}

function generate_cp() {
  echo "start generate and convert checkpoint image for functions..."
  criu check
  cd /var/lib/faasd
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no --no-bgtask &> $TEMPDIR/faasd.log &
  local faasd_pid=$!
  sleep 1
  
  cat /var/lib/faasd/secrets/basic-auth-password | faas-cli login -u admin --password-stdin \
    -g http://127.0.0.1:8081 
  
  #/root/test
  cd $WORKDIR
  faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "h-hello*"
  sleep 1
  curl http://127.0.0.1:8081/function/h-hello-world
  
  # generate and convert checkpoint
  # Maybe a solution is copy criu.kdat into /run/ beforehand 
  faasd checkpoint --dax-device /dev/dax0.0 --mem-pool dax h-hello-world
}

# setup open file descriptor limit
ulimit -n 102400
# disable swap
swapoff -a

# change owner of pkg directory
if [ ! -e /var/lib/faasd/pkgs ]; then
  echo "please make sure /var/lib/faasd/pkgs is exists"
  exit 1
fi
chown -R 100 /var/lib/faasd/pkgs/

kill_process faasd
kill_process containerd
start_containerd $TEMPDIR
download_ctr_images

# faasd install need resolve.conf and network.sh
cd /root/go/src/github.com/openfaas/faasd
faasd install

kill_ctrs
sleep 1
# enable_switch_criu
generate_cp

echo "machine prepare succeed!"
