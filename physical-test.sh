#!/bin/bash
set -e

WORKDIR=/root/test
TEMPDIR=/run

function cleanup() {
  echo "kill faasd"
  pkill faasd || true
  while true; do
    if ps -ef | grep "[p]rovider" ; then
      sleep 2
    else
      break
    fi
  done

  echo "kill fwatchdog"
  pkill -9 fwatchdog || true
  sleep 5

  echo "umount app overlay"
  for x in $(df -ah | grep home/app | awk '{print $NF}'); do
    umount $x
  done

  echo "clean containers"
  for name in $(ctr t ls -q); do
    ctr t kill -s 9 $name || true
  done
  sleep 1
  ctr c rm $(ctr c ls -q) || true

  for name in $(ctr -n openfaas-fn t ls -q); do
    ctr -n openfaas-fn t kill -s 9 $name || true
  done
  sleep 1
  ctr -n openfaas-fn c rm $(ctr -n openfaas-fn c ls -q) || true
  sleep 5

  local number_of_cts=$(ctr -n openfaas-fn c ls -q | wc -l)
  if [ $number_of_cts -ne 0 ]; then
    echo "kill container failed"
    exit 1
  fi
  number_of_cts=$(ctr c ls -q | wc -l)
  if [ $number_of_cts -ne 0 ]; then
    echo "kill container failed"
    exit 1
  fi

  echo "kill containerd"
  pkill containerd || true
  while true; do
    if ps -ef | grep "[c]ontainerd" ; then
      sleep 2
    else
      break
    fi
  done

  echo "umount overlay under /var/lib/faasd/app/merged/"
  umount /var/lib/faasd/app/merged/* || true
  rm -rf /var/lib/faasd/checkpoints/criu-r-workdir/*
}

function show_memory_usage() {
  while true; do
    date
    cat /sys/fs/cgroup/openfaas-fn/memory.current
    sleep 1
  done
}


function switch_test() {
  local mem=$1
  echo "start switching test..."
  cp /root/downloads/switch-criu /usr/local/sbin/criu
  criu check

  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no --mem $mem &> $TEMPDIR/faasd.log &
  local faasd_pid=$!
  sleep 30
  
  cd $WORKDIR
  # register new container
  faas-cli register -f $WORKDIR/stack.yml -g http://127.0.0.1:8081
  sleep 2

  show_memory_usage &> $TEMPDIR/memory_stat.output &
  local mem_stat_pid=$!
  mpstat 1 > $TEMPDIR/mpstat.output &
  local mpstat_pid=$!

  source /root/miniconda3/bin/activate faasd-test
  cd faasd-testdriver
  python main.py 2>&1 | tee $TEMPDIR/test.log
   
  curl http://127.0.0.1:8081/system/metrics > $TEMPDIR/metrics.output
  kill $mpstat_pid
  kill $mem_stat_pid
  # kill $faasd_pid
}

function baseline_test() {
  local mem=$1
  local gc=$2
  echo "start baseline test..."
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no --baseline --mem $mem --gc ${gc} &> $TEMPDIR/faasd.log &
  local faasd_pid=$!
  sleep 15
  
  cd $WORKDIR
  # register new container
  faas-cli register -f $WORKDIR/stack.yml -g http://127.0.0.1:8081
  sleep 2

  show_memory_usage &> $TEMPDIR/memory_stat.output &
  local mem_stat_pid=$!
  mpstat 1 > $TEMPDIR/mpstat.output &
  local mpstat_pid=$!

  source /root/miniconda3/bin/activate faasd-test
  cd faasd-testdriver
  python main.py 2>&1 | tee $TEMPDIR/test.log
   
  curl http://127.0.0.1:8081/system/metrics > $TEMPDIR/metrics.output
  kill $mpstat_pid || true
  kill $mem_stat_pid || true
  # kill $faasd_pid
}

function criu_test() {
  local mem=$1
  local gc=$2
  echo "start raw criu test..."
  cp /root/downloads/baseline-criu /usr/local/sbin/criu
  criu check

  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no --baseline --criu --mem $mem --gc $gc &> $TEMPDIR/faasd.log &
  local faasd_pid=$!
  sleep 15
  
  cd $WORKDIR
  # register new container
  faas-cli register -f $WORKDIR/stack.yml -g http://127.0.0.1:8081
  sleep 2

  show_memory_usage &> $TEMPDIR/memory_stat.output &
  local mem_stat_pid=$!
  mpstat 1 > $TEMPDIR/mpstat.output &
  local mpstat_pid=$!

  source /root/miniconda3/bin/activate faasd-test
  cd faasd-testdriver
  python main.py 2>&1 | tee $TEMPDIR/test.log
   
  curl http://127.0.0.1:8081/system/metrics > $TEMPDIR/metrics.output
  kill $mpstat_pid || true
  kill $mem_stat_pid || true
  # kill $faasd_pid
}

function functional_test() {
  echo "start functional test..."
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no --no-bgtask --baseline --criu &> $TEMPDIR/faasd.log &
  sleep 1

  cd $WORKDIR
  # register new container
  faas-cli register -f $WORKDIR/stack.yml -g http://127.0.0.1:8081
  sleep 2

  rm /root/test/*.log

  curl http://127.0.0.1:8081/invoke/h-hello-world
  
  # belows are all switch by default
  for ((i = 1; i <= 1; i++)); do
    # curl -X POST http://127.0.0.1:8081/invoke/h-memory -d '{"size": 12345678}'
    curl -X POST http://127.0.0.1:8081/invoke/pyaes -d '{"length_of_message": 4000, "num_of_iterations": 120}' >> pyaes.log
    
    curl http://127.0.0.1:8081/invoke/image-processing >> image-processing.log
    
    curl http://127.0.0.1:8081/invoke/image-recognition >> image-recognition.log
    
    curl http://127.0.0.1:8081/invoke/video-processing >> video-processing.log
    
    curl -X POST -d '{"num_of_rows": 500, "num_of_cols": 500}' http://127.0.0.1:8081/invoke/chameleon >> chameleon.log
    
    curl -X POST -d '{"username": "Peking", "random_len": 1554}' http://127.0.0.1:8081/invoke/dynamic-html >> dynamic-html.log
  
    curl -X POST -H "Content-Type: application/json" -d '{"length_of_message": 2000, "num_of_iterations": 10000}' http://127.0.0.1:8081/invoke/crypto >> crypto.log
  
    curl http://127.0.0.1:8081/invoke/image-flip-rotate >> image-flip-rotate.log
  done

  curl http://127.0.0.1:8081/system/metrics > metrics.output

  for file in $(ls *.log); do
    grep -Po 'latency":([0-9\.]+)' $file > lat-${file}
  done
}

if [[ $1 == clean ]]; then
  echo "clean up only ..."
  cleanup
  exit 0
fi

if [ $# -ne 3 ]; then
  echo "usgae: bash physical-test.sh [TEST NAME] [MEM BOUND] [GC]"
  exit 1
fi

TEST_CLASS=$1
OUTPUT=/root/test/result/$TEST_CLASS
MEM_BOUND=$2
GC_TIME=$3

echo "TEST NAME: $TEST_CLASS, MEM BOUND: $MEM_BOUND GC_TIME: $GC_TIME"

if [ -e $OUTPUT ]; then
  echo "output dir $OUTPUT exist, please remove it first!"
  exit 1
fi

# clean output from last round
cleanup
sleep 3
containerd -l debug &> $TEMPDIR/containerd.log &
sleep 5

if [[ $TEST_CLASS == baseline* ]]; then
  baseline_test $MEM_BOUND $GC_TIME
elif [[ $TEST_CLASS == switch* ]]; then
  switch_test $MEM_BOUND
elif [[ $TEST_CLASS == criu* ]]; then
  criu_test $MEM_BOUND $GC_TIME
elif [[ $TEST_CLASS == functional_test* ]]; then
  functional_test
else
  echo "unknown test class: $TEST_CLASS"
  exit 1
fi

