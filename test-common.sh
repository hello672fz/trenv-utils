#!/bin/bash

WORKDIR=/root/test
TEMPDIR=/run
OUTDIR=/root/test/result
RAW_CRIU_PATH=/root/downloads/raw-criu
SWITCH_CRIU_PATH=/root/downloads/switch-criu
LAZY_CRIU_PATH=/root/downloads/lazy-criu
FAASNAP_DIR=/root/faasnap/faasnap

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
  if [ -e /root/downloads/raw-criu.kdat ]; then
    cp /root/downloads/raw-criu.kdat /run/criu.kdat
  fi
  echo "start criu check..."
  criu check
  echo "criu check finish"
  cp /run/criu.kdat /root/downloads/raw-criu.kdat
}

function enable_lazy_criu() {
  cp $LAZY_CRIU_PATH /usr/local/sbin/criu
  if [ -e /root/downloads/lazy-criu.kdat ]; then
    cp /root/downloads/lazy-criu.kdat /run/criu.kdat
  fi
  echo "start criu check..."
  criu check
  echo "criu check finish"
  cp /run/criu.kdat /root/downloads/lazy-criu.kdat
}

function enable_switch_criu() {
  cp $SWITCH_CRIU_PATH /usr/local/sbin/criu
  if [ -e /root/downloads/switch-criu.kdat ]; then
    cp /root/downloads/switch-criu.kdat /run/criu.kdat
  fi
  echo "start criu check..."
  criu check
  echo "criu check finish"
  cp /run/criu.kdat /root/downloads/switch-criu.kdat
}

function enable_reuse_criu() {
  cp /root/downloads/reuse-criu /usr/local/sbin/criu
  if [ -e /root/downloads/reuse-criu.kdat ]; then
    cp /root/downloads/reuse-criu.kdat /run/criu.kdat
  fi
  echo "start criu check..."
  criu check
  echo "criu check finish"
  cp /run/criu.kdat /root/downloads/reuse-criu.kdat
}

function enable_cgroup_criu() {
  cp /root/downloads/cgroup-criu /usr/local/sbin/criu
  if [ -e /root/downloads/cgroup-criu.kdat ]; then
    cp /root/downloads/cgroup-criu.kdat /run/criu.kdat
  fi
  echo "start criu check..."
  criu check
  echo "criu check finish"
  cp /run/criu.kdat /root/downloads/cgroup-criu.kdat
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
  if pkill -x "$process_name"; then
    sleep 1
    if pgrep -x "$process_name" > /dev/null; then
      pkill -9 -x $process_name || true
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

function clean_fc_netns() {
  local n
  local id
  for n in $(ip netns list); do
    if echo $n | grep -P "fc\d+" &> /dev/null; then 
      id=${n:2}
      ip netns delete $n
      echo "delete namespace $n"
    fi
  done
}

function is_process_exist() {
  local name=$1
  if pgrep -x $name > /dev/null; then
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
  setsid containerd -l debug &> $tmp_dir/containerd.log &
  sleep 5
}


# Only used by test.sh for now
# argument:
# 1: mem bound (in GB)
# 2: is_baseline (boolean)
# 3: start_method ("cold" or "criu")
# 4: no_bg_task (boolean)
# 5: gc_criterion (in minutes)
# 6: no_reuse (boolean)
# 7: idle_num (integer)
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
  local no_reuse=$6
  local idle_num=$7

  local args="--mem ${mem_bound}"
  if [ $is_baseline -eq 1 ]; then
    args="${args} --baseline"
  fi
  if [ ! -z "${start_method}" ]; then
    args="${args} --start-method ${start_method}"
    if [ "${start_method}" == "criu" ]; then
      enable_raw_criu
    elif [ "${start_method}" == "lazy" ]; then
      enable_lazy_criu
    else
      enable_switch_criu
      # enable_reuse_criu
      # enable_cgroup_criu
    fi
  fi
  if [ $no_bg_task -eq 1 ]; then
    args="${args} --no-bgtask"
  fi
  if [ ! -z "${gc_criterion}" ]; then
    args="${args} --gc ${gc_criterion}"
  fi
  if [ $no_reuse -eq 1 ]; then
    args="${args} --no-reuse"
  fi
  if [ $idle_num -gt 0 ]; then
    args="${args} --idle-num ${idle_num}"
  fi
  echo "start faasd with args: ${args}"
  secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
    --pull-policy no ${args} &> $TEMPDIR/faasd.log &
  local faasd_pid=$!
  echo $faasd_pid
}

function get_cgroup_path() {
  local method=$1
  local cgroup_path=/sys/fs/cgroup/openfaas-fn
  if [ $method == "faasnap" ]; then
    cgroup_path=/sys/fs/cgroup/faasnap
  elif [ $method == "reap" ]; then
    cgroup_path=/sys/fs/cgroup/reap
  fi
  echo $cgroup_path
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
