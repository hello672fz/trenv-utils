#!/bin/bash

set -e

function gen_file_info() {
  local prefix=$1

  cd /root/qemu_linux/micro_bench/file_page_stat
  local p1=$(pgrep -x -f fwatchdog)
  if [ -z "$p1" ]; then
    echo "not found fwatchdog"
    exit 1
  fi
  ./file_page_stat $p1 $prefix
  local p2=$(pgrep -x -f 'python index.py'||true)
  local p3=$(pgrep -x -f 'node index.js'||true)
  if [ -z "$p2" ] && [ -z "$p3" ]; then
    echo "do not find node or py"
    exit 1
  fi
  if [ ! -z "$p2" ] && [ ! -z "$p3" ]; then
    echo "find both node or py"
    exit 1
  fi
  if [ ! -z "$p2" ]; then
    ./file_page_stat $p2 $prefix
  fi
  if [ ! -z "$p3" ]; then
    ./file_page_stat $p3 $prefix
  fi

  cd -
}

# cd ../..
# bash test.sh --no-bgtask --no-test --baseline --start-method criu
# sleep 3
# cd -
containerd &> /run/containerd.log &
sleep 1
secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
  --pull-policy no --no-bgtask --baseline --start-method criu &> /run/faasd.log &
sleep 2

cd /root/test
# register new container
faas-cli register -f ./stack.yml -g http://127.0.0.1:8081
sleep 2


echo 1 > /proc/sys/vm/drop_caches
curl http://127.0.0.1:8081/invoke/h-hello-world
gen_file_info h-hello-world
curl http://127.0.0.1:8081/danger/kill
sleep 1

echo 1 > /proc/sys/vm/drop_caches
curl -X POST http://127.0.0.1:8081/invoke/pyaes -d '{"length_of_message": 4000, "num_of_iterations": 120}'
gen_file_info pyaes
curl http://127.0.0.1:8081/danger/kill
sleep 1

echo 1 > /proc/sys/vm/drop_caches
curl http://127.0.0.1:8081/invoke/image-processing
gen_file_info image-processing
curl http://127.0.0.1:8081/danger/kill
sleep 1

echo 1 > /proc/sys/vm/drop_caches
curl http://127.0.0.1:8081/invoke/image-recognition
gen_file_info image-recognition 
curl http://127.0.0.1:8081/danger/kill
sleep 1

echo 1 > /proc/sys/vm/drop_caches
curl http://127.0.0.1:8081/invoke/video-processing
gen_file_info video-processing
curl http://127.0.0.1:8081/danger/kill
sleep 1

echo 1 > /proc/sys/vm/drop_caches
curl -X POST -d '{"num_of_rows": 500, "num_of_cols": 500}' http://127.0.0.1:8081/invoke/chameleon &> chameleon.log
gen_file_info chameleon
curl http://127.0.0.1:8081/danger/kill
sleep 1

echo 1 > /proc/sys/vm/drop_caches
curl -X POST -d '{"username": "Peking", "random_len": 1554}' http://127.0.0.1:8081/invoke/dynamic-html &> dynamic-html.log
gen_file_info dynamic-html
curl http://127.0.0.1:8081/danger/kill
sleep 1

echo 1 > /proc/sys/vm/drop_caches
curl -X POST -H "Content-Type: application/json" -d '{"length_of_message": 2000, "num_of_iterations": 10000}' http://127.0.0.1:8081/invoke/crypto
gen_file_info crypto
curl http://127.0.0.1:8081/danger/kill
sleep 1

echo 1 > /proc/sys/vm/drop_caches
curl http://127.0.0.1:8081/invoke/image-flip-rotate
gen_file_info image-flip-rotate
curl http://127.0.0.1:8081/danger/kill
sleep 1


echo 1 > /proc/sys/vm/drop_caches
curl -X POST http://127.0.0.1:8081/invoke/json-serde -d '{"name": "3"}'
gen_file_info json-serde
curl http://127.0.0.1:8081/danger/kill
sleep 1

echo 1 > /proc/sys/vm/drop_caches
curl -X POST -H "Content-Type: application/json" -d '{"name": "5"}' http://127.0.0.1:8081/invoke/js-json-serde
gen_file_info js-json-serde
curl http://127.0.0.1:8081/danger/kill
sleep 1

echo 1 > /proc/sys/vm/drop_caches
curl -X POST -d '{"size": 75000, "out": 12}' http://127.0.0.1:8081/invoke/pagerank
gen_file_info pagerank
curl http://127.0.0.1:8081/danger/kill
sleep 1
