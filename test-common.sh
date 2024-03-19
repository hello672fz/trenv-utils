#!/bin/bash

WORKDIR=/root/test
TEMPDIR=/run
OUTDIR=/root/test/result
RAW_CRIU_PATH=/root/downloads/raw-criu
SWITCH_CRIU_PATH=/root/downloads/switch-criu

if [ ! -e $RAW_CRIU_PATH ]; then
  echo "raw criu not exist: $RAW_CRIU_PATH"
  exit 1
fi
if [ ! -e $SWITCH_CRIU_PATH ]; then
  echo "switch criu not exist: $SWITCH_CRIU_PATH"
  exit 1
fi

# NOTE by huang-jl: the first time criu running will spent a lot of time querying kernel capabilities
# (more than 2 mins) , so here we run criu check and let it generates criu.kdat
function enable_raw_criu() {
  cp $RAW_CRIU_PATH /usr/local/sbin/criu
  echo "start criu check..."
  criu check
  echo "criu check finish"
}

function enable_switch_criu() {
  cp $SWITCH_CRIU_PATH /usr/local/sbin/criu
  echo "start criu check..."
  criu check
  echo "criu check finish"
}

function kill_ctrs() {
  local name
  for name in $(ctr t ls -q); do
    ctr t kill -s 9 $name || true
  done
  for name in $(ctr c ls -q); do
    ctr c rm $name
  done

  for name in $(ctr -n openfaas-fn t ls -q); do
    ctr -n openfaas-fn t kill -s 9 $name || true
  done
  for name in $(ctr -n openfaas-fn c ls -q); do
    ctr -n openfaas-fn c rm $name
  done
}

function kill_process() {
  local process_name="$1"
  local ret
  if [ -z "$process_name" ]; then
    echo "empty process name to kill"
  fi
  if pkill -f "$process_name"; then
    sleep 1
    if pgrep -f "$process_name" > /dev/null; then
      pkill -9 -f $process_name || true
    fi
  else
      # If fails to find the process, capture its exit status
      local pkill_exit_status=$?
      # If exits with 1 (indicating no matching process found), continue
      if [ $pkill_exit_status -eq 1 ]; then
          echo "process $process_name does not exist, cannot kill it"
      else
          # If pgrep exits with a non-zero status other than 1, exit the script with that status
          echo "Error: pkill failed with exit status $pkill_exit_status"
          exit $pkill_exit_status
      fi
  fi
}

function is_process_exist() {
  local name=$1
  if pgrep -f $name > /dev/null; then
    echo "true"
  else 
    local pgrep_exit_status=$?
    # If exits with 1 (indicating no matching process found), continue
    if [ $pgrep_exit_status -eq 1 ]; then
      echo "false"
    else
        # If pgrep exits with a non-zero status other than 1, exit the script with that status
        echo "Error: pkill failed with exit status $pgrep_exit_status"
        exit $pgrep_exit_status
    fi
  fi
}

function start_containerd() {
  local tmp_dir=$1
  sleep 1
  if [ $(is_process_exist containerd) == "true" ]; then
    echo "containerd is running, kill it first"
    exit 1
  fi
  echo "start containerd..."
  containerd -l debug &> $tmp_dir/containerd.log &
  sleep 5
}


# argument:
# 1: mem bound (in GB)
# 2: is_baseline
# 3: start_method ("cold" or "criu")
# 4: no_bg_task
# 5: gc_criterion (in minutes)
#
# exmaple:
# 32GB is_baseline:true start_method:cold no_bg_task:true gc_criterion:10
# start_faasd 32 1 cold 1 10
function start_faasd() {
  local mem_bound=$1
  local is_baseline=$2
  local start_method=$3
  local no_bg_task=$4
  local gc_criterion=$5
  local args="--mem ${mem_bound}"
  if [ $is_baseline -eq 1 ]; then
    args="${args} --baseline"
  fi
  if [ ! -z "${start_method}" ]; then
    args="${args} --start-method ${start_method}"
    if [ "${start_method}" == "criu" ]; then
      enable_raw_criu
    else
      enable_switch_criu
    fi
  fi
  if [ $no_bg_task -eq 1 ]; then
    args="${args} --no-bgtask"
  fi
  if [ ! -z "${gc_criterion}" ]; then
    args="${args} --gc ${gc_criterion}"
  fi
  echo "start faasd with args: ${args}"
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no ${args} &> $TEMPDIR/faasd.log &
  local faasd_pid=$!
  echo $faasd_pid
}

# Different machine might use different python
# virtual environment manager.
# Please activate the python environment that is
# suitable for test driver
function activate_test_driver_env() {
  # source /root/miniconda3/bin/activate faasd-test
  # source /root/app/test/bin/activate
  source /root/venv/faasd-test/bin/activate
}
