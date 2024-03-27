#!/bin/bash
set -e

# Example
# baseline test:
# --baseline --gc 10 --start-method cold
# criu test:
# --baseline --start-method criu --gc 10

MEM=64  # default 64G
IS_BASELINE=0 # default not baseline
START_METHOD="cold" # default cold start
GC_CRITERION=10 # default gc is 10 min
NO_BG_TASK=0  # default enable bg task
TEST_NAME=""
FUNCTIONAL_ITER=0
NO_TEST=0

# import test-common.sh
THIS=`readlink -f "${BASH_SOURCE[0]}" 2>/dev/null||echo $0`
DIR=`dirname "${THIS}"`
. "$DIR/test-common.sh"


function cleanup() {
  kill_process faasd
  sleep 2
  kill_process fwatchdog
  echo "umount app overlay"
  for x in $(df -ah | grep home/app | awk '{print $NF}'); do
    umount $x
  done

  echo "clean containers"
  kill_ctrs

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
  kill_process containerd
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


function start_test {
  echo "start normal test"
  cd $WORKDIR
  # register new container
  faas-cli register -f $WORKDIR/stack.yml -g http://127.0.0.1:8081
  sleep 2

  show_memory_usage &> $TEMPDIR/memory_stat.output &
  local mem_stat_pid=$!
  mpstat 1 > $TEMPDIR/mpstat.output &
  local mpstat_pid=$!

  activate_test_driver_env
  cd faasd-testdriver
  python main.py 2>&1 | tee $TEMPDIR/test.log
   
  curl http://127.0.0.1:8081/system/metrics > $TEMPDIR/metrics.output
  kill $mpstat_pid
  kill $mem_stat_pid
}

function functional_test() {
  local iter=$1
  echo "start functional test..."

  cd $WORKDIR
  # register new container
  faas-cli register -f $WORKDIR/stack.yml -g http://127.0.0.1:8081
  sleep 2

  rm -f $WORKDIR/*.log

  curl http://127.0.0.1:8081/invoke/h-hello-world
  # belows are all switch by default
  for ((i = 1; i <= $iter; i++)); do
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
  curl http://127.0.0.1:8081/system/metrics > $TEMPDIR/metrics.output
  for file in $(ls *.log); do
    grep -Po 'latency":([0-9\.]+)' $file > lat-${file}
  done
}


function collect_result() {
  local output_dir=$1
  echo "copying result to $output_dir..."
  
  mkdir -p $output_dir
  mv $TEMPDIR/metrics.output $output_dir
  if [ -e $TEMPDIR/memory_stat.output ]; then
    mv $TEMPDIR/memory_stat.output  $output_dir
  fi
  if [ -e $TEMPDIR/mpstat.output ]; then
    mv $TEMPDIR/mpstat.output $output_dir
  fi
  mv $TEMPDIR/faasd.log $output_dir
  if [ -e $TEMPDIR/test.log ]; then
    mv $TEMPDIR/test.log $output_dir
  fi
  cp $TEMPDIR/containerd.log $output_dir
  cp $WORKDIR/faasd-testdriver/workload.json $output_dir
  cp $WORKDIR/faasd-testdriver/gen_trace.py $output_dir
  # cp /root/go/src/github.com/openfaas/faasd/pkg/constants.go $output_dir
}

function print_help_message() {
  cat >&2 << helpMessage

  Usage: ${0##*/} <OPTIONS> <TEST_NAME>

    Test helper scripts. TEST_NAME is used to as the name of output dir of this test.


  OPTIONS:

    --mem <MEM>             The software limitation of memory in GB, default is 64GB.
    --start-method <METHOD> Start method used by faasd, currently only support cold and criu, default is cold.
    --gc <TIME>             The period of garbage routine to scan, in Minute. (Only useful when --baseline)
                            Default is 10 min.
    --no-bgtask             Disable the background task in faasd.
    --baseline              Start faasd in baseline mode.
    --functional            Start functional test, this will not using faasd-testdriver and not using trace to test.
                            Note that functional_test will not collect result to output dir.
    --clean                 This will clean the process used by test (including containers, fassd and containerd)
                            , unmount the overlayfs and remove the criu-r-workdir. This should called before start
                            a new round of test.
    -h | --help             Print this help message.


helpMessage
}


# parse argument
while [[ $# -gt 0 ]]; do
  case $1 in
    --mem)
      MEM=$2
      shift # past argument
      shift # past value
      ;;
    --baseline)
      IS_BASELINE=1
      shift
      ;;
    --start-method)
      START_METHOD="$2"
      shift
      shift
      ;;
    --clean)
      cleanup
      exit 0
      ;;
    --no-bgtask)
      NO_BG_TASK=1
      shift
      ;;
    --gc|--gc-criterion)
      GC_CRITERION=$2
      shift
      shift
      ;;
    --functional)
      FUNCTIONAL_ITER=$2
      shift
      shift
      ;;
    --no-test)
      NO_TEST=1
      shift
      ;;
    -h|--help)
      print_help_message
      exit 0
      ;;
    *)
      if [ -z "$TEST_NAME" ]; then
        TEST_NAME=$1
        shift
      else
        echo "Unknown argument $1"
        exit 1
      fi
      ;;
  esac
done

output=${OUTDIR}/${TEST_NAME}
if [ -e $output ] && [ $NO_TEST -eq 0 ]; then
  echo "output dir $output exist, please remove it first!"
  exit 1
fi

start_containerd $TEMPDIR
sleep 5

if [ $(is_process_exist faasd) == "true" ]; then
  echo "faasd is still running"
  exit 1
fi
start_faasd $MEM $IS_BASELINE $START_METHOD $NO_BG_TASK $GC_CRITERION
if [ $NO_TEST -eq 1 ]; then
  exit 0
fi

sleep 20
if [ $FUNCTIONAL_ITER -ge 1 ]; then
  functional_test $FUNCTIONAL_ITER
else
  start_test
fi
collect_result $output
