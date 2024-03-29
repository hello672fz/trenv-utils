#!/bin/bash
set -e

# What need to be put into WORKDIR:
# stack.yml: contains the infomation of lambdas (e.g., docker images), copy the stack.yml in this repo is ok.
# templates: directory containes the template of lang used by lambda (i.e., hybrid-py and hyprid-js)
#             which can be symbol link of faasd-testdriver/functions/template
# faasd-testdriver: faasd-testdriver repository, which contains the client test codes.
# resolve.conf: which can be copied from this repo.
# pseudo-mm-rdma-server

ETH_INTERFACE=eth0
DAX_DEVICE="/dev/dax0.0"
POOL_TYPE="dax"

THIS=`readlink -f "${BASH_SOURCE[0]}" 2>/dev/null||echo $0`
DIR=`dirname "${THIS}"`
. "$DIR/test-common.sh"


function prepare_rxe() {
  while true; do
    read -p "start configure rxe ${ETH_INTERFACE} in [RDMA] mode? " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit 1;;
        * ) echo "Please answer yes or no.";;
    esac
  done
  if ! ip addr show ${ETH_INTERFACE}; then
    ip link add  ${ETH_INTERFACE} type dummy
    ip address add 172.16.2.1/24 dev ${ETH_INTERFACE}
    ip link set ${ETH_INTERFACE} up
  fi
  # create rxe device
  if ! rdma link | grep ${ETH_INTERFACE} ; then
    rdma link add rxe_${ETH_INTERFACE} type rxe netdev ${ETH_INTERFACE}
  fi
  if ! lsmod | grep pseudo_mm_rdma; then
    echo "do not found pseudo_mm_rdma modules, start rdma server and insmod..."
    stdbuf -o0 ${WORKDIR}/pseudo-mm-rdma-server 50000 &> $TEMPDIR/rdma-server.log &
    local ip_address=$(ip -f inet addr show ${ETH_INTERFACE} | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')
    echo "prepare rxe for interface $ETH_INTERFACE: ip address is ${ip_address}"
    sleep 5
    modprobe pseudo_mm_rdma sport=50000 sip="${ip_address}" cip="${ip_address}"
  fi
}

function download_ctr_images() {
  local apps=(h-hello-world h-memory pyaes image-processing video-processing \
    image-recognition chameleon dynamic-html crypto image-flip-rotate \
    json-serde js-json-serde pagerank )
  for app in ${apps[@]}; do
    local img_name=docker.io/jialianghuang/${app}:latest
    local output=$(ctr -n openfaas-fn image check "name==${img_name}")
    if [ -z "${output}" ]; then
      # do not found image in containerd
      echo "start pull docker image for $app ..."
      ctr image pull $img_name
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
  
  cd $WORKDIR
  faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "h-hello*"
  sleep 1
  curl http://127.0.0.1:8081/function/h-hello-world
  
  faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "h-mem*"
  sleep 1
  curl -X POST http://127.0.0.1:8081/function/h-memory -d '{"size": 134217728}'

  faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "json-serde"
  sleep 1
  curl -X POST http://127.0.0.1:8081/function/json-serde -d '{"name": "2"}'

  faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "js-json-serde"
  sleep 1
  curl -X POST -H "Content-Type: application/json" http://127.0.0.1:8081/function/js-json-serde -d '{"name": "2"}'

  faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "pagerank"
  sleep 1
  curl -X POST http://127.0.0.1:8081/function/pagerank -d '{"size": 70000}'
  
  for id in "" "_1" "_2"; do
    faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "pyaes${id}"
    sleep 1
    curl -X POST http://127.0.0.1:8081/function/pyaes${id} -d '{"length_of_message": 2000, "num_of_iterations": 200}'
    
    faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "image-processing${id}"
    sleep 1
    curl http://127.0.0.1:8081/function/image-processing${id}
    
    faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "image-recognition${id}"
    sleep 3
    curl http://127.0.0.1:8081/function/image-recognition${id}
    
    faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "video-processing${id}"
    sleep 1
    curl http://127.0.0.1:8081/function/video-processing${id}
    
    faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "chameleon${id}"
    sleep 1
    curl -X POST -d '{"num_of_rows": 700, "num_of_cols": 400}' http://127.0.0.1:8081/function/chameleon${id} &> chameleon.output
    
    faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "dynamic-html${id}"
    sleep 1
    curl -X POST -d '{"username": "Tsinghua", "random_len": 1000}' http://127.0.0.1:8081/function/dynamic-html${id} &> dynamic-html.output
    
    faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "crypto${id}"
    sleep 1
    curl -X POST -H "Content-Type: application/json" -d '{"length_of_message": 2000, "num_of_iterations": 5000}' http://127.0.0.1:8081/function/crypto${id}
    
    faas-cli deploy --update=false -f $WORKDIR/stack.yml -g http://127.0.0.1:8081 --filter "image-flip-rotate${id}"
    sleep 1
    curl http://127.0.0.1:8081/function/image-flip-rotate${id}
  done
  
  # generate and convert checkpoint
  # Maybe a solution is copy criu.kdat into /run/ beforehand 
  faasd checkpoint --dax-device $DAX_DEVICE --mem-pool $POOL_TYPE h-hello-world h-memory \
    pyaes image-processing image-recognition video-processing chameleon dynamic-html crypto image-flip-rotate \
    json-serde js-json-serde pagerank \
    pyaes_1 image-processing_1 image-recognition_1 video-processing_1 chameleon_1 dynamic-html_1 crypto_1 image-flip-rotate_1 \
    pyaes_2 image-processing_2 image-recognition_2 video-processing_2 chameleon_2 dynamic-html_2 crypto_2 image-flip-rotate_2

  # clear container and restart faasd
  kill $faasd_pid
  for app in ${apps[@]}; do
    ctr -n openfaas-fn c rm $app
  done
}

function print_help_message() {
  cat >&2 << helpMessage

  Usage: ${0##*/} <OPTIONS>

    Machien prepare helper scripts. Only need to execute once since machine boot up.


  OPTIONS:

    --mem-pool <POOL>       Pool type of the memory image, currently only support rdma and dax, default is dax.
    --dax | --dax-dev       Dax device path, default is /dev/dax0.0
    --nic                   Network interface used by rxe (i.e., softroce), default is eth0
    -h | --help             Print this help message.


helpMessage
}


# parse argument
while [[ $# -gt 0 ]]; do
  case $1 in
    --dax|--dax-dev|--dax-device)
      DAX_DEVICE=$2
      shift
      shift
      ;;
    --mem-pool)
      POOL_TYPE=$2
      shift
      shift
      ;;
    --nic)
      ETH_INTERFACE=$2
      shift
      shift
      ;;
    -h|--help)
      print_help_message
      exit 0
      ;;
    *)
      echo "Unknown argument $1"
      exit 1
      ;;
  esac
done

# config cxl device if necessary
if [ "$POOL_TYPE" == "dax" ] && [ ! -e $DAX_DEVICE ]; then
  while true; do
    read -p "$DAX_DEVICE not exist, start configure it using region 0? " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit 1;;
        * ) echo "Please answer yes or no.";;
    esac
  done
  daxctl disable-device -r 0 all
  daxctl destroy-device -r 0 all || true
  daxctl create-device -r 0 -a 4096
fi

bash insmod.sh
if [ "$POOL_TYPE" == "rdma" ]; then
  prepare_rxe
fi

# task in prepare need only done once
# when the machine is boot up
#
# setup open file descriptor limit
ulimit -n 102400

# change owner of pkg directory
chown -R 100 /var/lib/faasd/pkgs/

kill_process faasd
kill_process containerd
start_containerd $TEMPDIR
download_ctr_images

cp resolv.conf $WORKDIR
cd $WORKDIR
faasd install
umount /var/lib/faasd/checkpoints || true
rm -rf /var/lib/faasd/checkpoints
mkdir -p /var/lib/faasd/checkpoints
mount -t tmpfs tmpfs /var/lib/faasd/checkpoints -o size=8G

kill_ctrs
sleep 1
enable_switch_criu
generate_cp

echo "machine prepare succeed!"
