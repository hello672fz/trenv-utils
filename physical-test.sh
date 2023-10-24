#!/bin/bash
set -e

WORKDIR=/root/test
TEMPDIR=/run

function show_memory_usage() {
  while true; do
    date
    free -h
    sleep 1
  done
}

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


function switch_test() {
  echo "start switching test..."
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no &> $TEMPDIR/faasd.log &
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

  source /root/venv/faasd-test/bin/activate
  cd faasd-testdriver
  python main.py 2>&1 | tee $TEMPDIR/test.log
   
  curl http://127.0.0.1:8081/system/metrics > $TEMPDIR/metrics.output
  kill $mpstat_pid
  kill $mem_stat_pid
  # kill $faasd_pid
}

function baseline_test() {
  echo "start baseline test..."
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no --baseline &> $TEMPDIR/faasd.log &
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

  source /root/venv/faasd-test/bin/activate
  cd faasd-testdriver
  python main.py 2>&1 | tee $TEMPDIR/test.log
   
  curl http://127.0.0.1:8081/system/metrics > $TEMPDIR/metrics.output
  kill $mpstat_pid
  kill $mem_stat_pid
  # kill $faasd_pid
}

function functional_test() {
  echo "start functional test..."
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no --no-bgtask &> $TEMPDIR/faasd.log &
  sleep 1

  cd $WORKDIR
  # register new container
  faas-cli register -f $WORKDIR/stack.yml -g http://127.0.0.1:8081
  sleep 2

  curl http://127.0.0.1:8081/invoke/h-hello-world
  
  # belows are all switch by default
  for ((i = 1; i <= 3; i++)); do
    curl -X POST http://127.0.0.1:8081/invoke/h-memory -d '{"size": 12345678}'
    
    curl -X POST http://127.0.0.1:8081/invoke/pyaes -d '{"length_of_message": 4000, "num_of_iterations": 120}'
    
    curl http://127.0.0.1:8081/invoke/image-processing
    
    curl http://127.0.0.1:8081/invoke/image-recognition
    
    curl http://127.0.0.1:8081/invoke/video-processing
    
    curl -X POST -d '{"num_of_rows": 500, "num_of_cols": 500}' http://127.0.0.1:8081/invoke/chameleon &> chameleon-${i}-cr.log
    
    curl -X POST -d '{"username": "Peking", "random_len": 1554}' http://127.0.0.1:8081/invoke/dynamic-html &> dynamic-html-${i}-cr.log
  
    curl -X POST -H "Content-Type: application/json" -d '{"length_of_message": 2000, "num_of_iterations": 10000}' http://127.0.0.1:8081/invoke/crypto
  
    curl http://127.0.0.1:8081/invoke/image-flip-rotate
  done

  curl http://127.0.0.1:8081/system/metrics > $TEMPDIR/metrics.output
}

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 [switch | baseline | functional_test]"
  exit 1
fi

TEST_CLASS=$1
OUTPUT=/root/test/result/$TEST_CLASS

if [ -e $OUTPUT ]; then
  echo "output dir $OUTPUT exist, please remove it first!"
  exit 1
fi

# clean output from last round
rm -rf /var/lib/faasd/checkpoints/criu-r-workdir/*

pkill faasd || true
sleep 3
pkill containerd || true
sleep 1
containerd -l debug &> $TEMPDIR/containerd.log &
sleep 5
kill_ctrs
sleep 5

if [[ $TEST_CLASS == baseline* ]]; then
  baseline_test
elif [[ $TEST_CLASS == switch* ]]; then
  switch_test
elif [[ $TEST_CLASS == functional_test* ]]; then
  functional_test
else
  echo "unknown test class: $TEST_CLASS"
  exit 1
fi

mkdir -p $OUTPUT
mv $TEMPDIR/metrics.output $OUTPUT
mv $TEMPDIR/memory_stat.output $OUTPUT
mv $TEMPDIR/mpstat.output $OUTPUT
mv $TEMPDIR/faasd.log $OUTPUT
mv $TEMPDIR/containerd.log $OUTPUT
mv $TEMPDIR/test.log $OUTPUT
cp $WORKDIR/faasd-testdriver/workload.json $OUTPUT
