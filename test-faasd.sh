#!/bin/bash
set -e

function show_memory_usage() {
  while true; do
    date
    free -h
    sleep 1
  done
}


function clean_output() {
  echo "clean previous output..."
  rm -f /root/faasd.log
  rm -f /root/test.log
  rm -f /root/metrics.output
  rm -f /root/mpstat.output
}

# task in prepare need only done once
# when the machine is boot up
function prepare() {
  # setup open file descriptor limit
  ulimit -n 102400
  
  # change owner of pkg directory
  chown -R 100 /var/lib/faasd/pkgs/
  
  if [ -f /root/criu.kdat ]; then
    echo "copying criu.kdat..."
    cp /root/criu.kdat /run
  fi
  
  rm -f /usr/bin/criu
  cp /root/criu  /tmp
  ln -s /tmp/criu /usr/bin/criu

  echo "start containerd and download container images..."
  containerd -l debug &> /tmp/containerd.log &
  sleep 5

  # download images
  apps=(h-hello-world h-memory pyaes image-processing video-processing \
    image-recognition chameleon dynamic-html crypto image-flip-rotate)
  for app in ${apps[@]}; do
    echo "start download $app ..."
    ctr image pull docker.io/jialianghuang/${app}:latest
  done

  rm -rf /var/lib/faasd/checkpoints
  mkdir -p /var/lib/faasd/checkpoints
  mount -t tmpfs tmpfs /var/lib/faasd/checkpoints -o size=4G
}

function kill_ctrs() {
  ctr c rm $(ctr c ls -q) || true
  ctr -n openfaas-fn c rm $(ctr -n openfaas-fn c ls -q) || true
}

function generate_cp() {
  echo "start generate and convert checkpoint image for functions..."
  faasd install
  cd /var/lib/faasd
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no --no-bgtask &> /tmp/faasd.log &
  local faasd_pid=$!
  sleep 1
  
  cat /var/lib/faasd/secrets/basic-auth-password | faas-cli login -u admin --password-stdin \
    -g http://127.0.0.1:8081 
  
  cd /root
  faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "h-hello*"
  sleep 1
  curl http://127.0.0.1:8081/function/h-hello-world
  
  faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "h-mem*"
  sleep 1
  curl -X POST http://127.0.0.1:8081/function/h-memory -d '{"size": 134217728}'
  
  for id in "" "_1" "_2"; do
    faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "pyaes${id}"
    sleep 1
    curl -X POST http://127.0.0.1:8081/function/pyaes${id} -d '{"length_of_message": 2000, "num_of_iterations": 200}'
    
    faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "image-processing${id}"
    sleep 1
    curl http://127.0.0.1:8081/function/image-processing${id}
    
    faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "image-recognition${id}"
    sleep 3
    curl http://127.0.0.1:8081/function/image-recognition${id}
    
    faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "video-processing${id}"
    sleep 1
    curl http://127.0.0.1:8081/function/video-processing${id}
    
    faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "chameleon${id}"
    sleep 1
    curl -X POST -d '{"num_of_rows": 700, "num_of_cols": 400}' http://127.0.0.1:8081/function/chameleon${id} &> chameleon.output
    
    faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "dynamic-html${id}"
    sleep 1
    curl -X POST -d '{"username": "Tsinghua", "random_len": 1000}' http://127.0.0.1:8081/function/dynamic-html${id} &> dynamic-html.output
    
    faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "crypto${id}"
    sleep 1
    curl -X POST -H "Content-Type: application/json" -d '{"length_of_message": 2000, "num_of_iterations": 5000}' http://127.0.0.1:8081/function/crypto${id}
    
    faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "image-flip-rotate${id}"
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

  cp /run/criu.kdat /root

  # clear container and restart faasd
  kill $faasd_pid
  for app in ${apps[@]}; do
    ctr -n openfaas-fn c rm $app
  done
}

function switch_test() {
  echo "start switching test..."
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no &> /tmp/faasd.log &
  local faasd_pid=$!
  sleep 30
  
  # register new container
  faas-cli register -f /root/stack.yml -g http://127.0.0.1:8081
  sleep 2

  mpstat 1 > /tmp/mpstat.output &
  local mpstat_pid=$!
  source /root/app/test/bin/activate
  cd /root/faasd-testdriver
  python main.py 2>&1 | tee /tmp/test.log
   
  curl http://127.0.0.1:8081/system/metrics > /tmp/metrics.output
  kill $mpstat_pid
  # kill $faasd_pid
}

function baseline_test() {
  echo "start baseline test..."
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no --baseline &> /tmp/faasd.log &
  local faasd_pid=$!
  sleep 15
  
  # register new container
  faas-cli register -f /root/stack.yml -g http://127.0.0.1:8081
  sleep 2

  show_memory_usage &> /tmp/memory_stat.output &
  local mem_stat_pid=$!
  mpstat 1 > /tmp/mpstat.output &
  local mpstat_pid=$!
  source /root/app/test/bin/activate
  cd /root/faasd-testdriver
  python main.py 2>&1 | tee /tmp/test.log
   
  curl http://127.0.0.1:8081/system/metrics > /tmp/metrics.output
  kill $mpstat_pid
  kill $mem_stat_pid
  # kill $faasd_pid
}

function functional_test() {
  echo "start functional test..."
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no --no-bgtask &> /tmp/faasd.log &
  sleep 1
  # register new container
  faas-cli register -f /root/stack.yml -g http://127.0.0.1:8081
  sleep 2

  curl http://127.0.0.1:8081/invoke/h-hello-world
  
  # belows are all switch by default
  for ((i = 1; i <= 3; i++)); do
    for id in "" "_1" "_2"; do
      curl -X POST http://127.0.0.1:8081/invoke/h-memory$id -d '{"size": 12345678}'
      
      curl -X POST http://127.0.0.1:8081/invoke/pyaes$id -d '{"length_of_message": 4000, "num_of_iterations": 120}'
      
      curl http://127.0.0.1:8081/invoke/image-processing$id
      
      curl http://127.0.0.1:8081/invoke/image-recognition$id
      
      curl http://127.0.0.1:8081/invoke/video-processing$id
      
      curl -X POST -d '{"num_of_rows": 500, "num_of_cols": 500}' http://127.0.0.1:8081/invoke/chameleon$id &> chameleon-${i}-cr.log
      
      curl -X POST -d '{"username": "Peking", "random_len": 1554}' http://127.0.0.1:8081/invoke/dynamic-html$id &> dynamic-html-${i}-cr.log
  
      curl -X POST -H "Content-Type: application/json" -d '{"length_of_message": 2000, "num_of_iterations": 10000}' http://127.0.0.1:8081/invoke/crypto$id
  
      curl http://127.0.0.1:8081/invoke/image-flip-rotate$id
    done
  done

  curl http://127.0.0.1:8081/system/metrics > /tmp/metrics.output
}


dmesg -D
clean_output
prepare
kill_ctrs
generate_cp

sleep 1

#switch_test
#baseline_test
functional_test

echo "Finish testing, copying logs..."
cp /tmp/faasd.log /root
cp /tmp/test.log /root
cp /tmp/metrics.output /root
cp /tmp/mpstat.output /root
sync
