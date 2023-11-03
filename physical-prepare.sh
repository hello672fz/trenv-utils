#!/bin/bash
set -e

WORKDIR=/root/test
TEMPDIR=/run

function kill_ctrs() {
  for name in $(ctr t ls -q); do
    ctr t kill -s 9 $name
  done
  ctr c rm $(ctr c ls -q) || true

  for name in $(ctr -n openfaas-fn t ls -q); do
    ctr -n openfaas-fn t kill -s 9 $name
  done
  ctr -n openfaas-fn c rm $(ctr -n openfaas-fn c ls -q) || true
}

function generate_cp() {
  echo "start generate and convert checkpoint image for functions..."
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
  # NOTE by huang-jl: the first time criu running will spent a lot of time querying kernel capabilities
  # (about 2 mins) so this will spent a lot of time
  # Maybe a solution is copy criu.kdat into /run/ beforehand 
  faasd checkpoint h-hello-world h-memory \
    pyaes image-processing image-recognition video-processing chameleon dynamic-html crypto image-flip-rotate \
    pyaes_1 image-processing_1 image-recognition_1 video-processing_1 chameleon_1 dynamic-html_1 crypto_1 image-flip-rotate_1 \
    pyaes_2 image-processing_2 image-recognition_2 video-processing_2 chameleon_2 dynamic-html_2 crypto_2 image-flip-rotate_2

  # clear container and restart faasd
  kill $faasd_pid
  for app in ${apps[@]}; do
    ctr -n openfaas-fn c rm $app
  done
}

pkill containerd || true
pkill faasd || true
sleep 2
# task in prepare need only done once
# when the machine is boot up
#
# setup open file descriptor limit
ulimit -n 102400

# change owner of pkg directory
chown -R 100 /var/lib/faasd/pkgs/

echo "start containerd and download container images..."
containerd -l debug &> $TEMPDIR/containerd.log &
sleep 5

# download images
apps=(h-hello-world h-memory pyaes image-processing video-processing \
  image-recognition chameleon dynamic-html crypto image-flip-rotate)
for app in ${apps[@]}; do
  echo "start download $app ..."
  ctr image pull docker.io/jialianghuang/${app}:latest
done

cp resolv.conf $WORKDIR
cd $WORKDIR
faasd install
rm -rf /var/lib/faasd/checkpoints
mkdir -p /var/lib/faasd/checkpoints
mount -t tmpfs tmpfs /var/lib/faasd/checkpoints -o size=16G

kill_ctrs

generate_cp

sleep 1
