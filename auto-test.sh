#!/bin/bash
#
RES_DIR=/root/test/result

is_integer() {
    local s=$1
    # Return true (0) if the variable is an integer, false (1) otherwise
    [[ $s =~ ^-?[0-9]+$ ]] && return 0 || return 1
}

suffix=$1
shift

curr_dir=$(pwd)
cd /root/test/faasd-testdriver
if [[ $suffix == azure ]]; then
  echo "generating azure trace..."
  python gen_trace.py -w azure --dataset /root/downloads/azurefunction-dataset2019
elif [[ $suffix == ali ]]; then
  echo "generating ali trace..."
  python gen_trace.py -w ali --dataset /root/downloads/data_training/dataSet_3
else
  echo "unknown suffix $suffix"
  exit 1
fi
cd $curr_dir

for mem in "$@"; do
  if ! is_integer $mem; then
    echo "only accept integer"
    exit 1
  fi

  if [ $mem -ge 256 ]; then
    echo "mem $mem is >= 256!"
    exit 1
  fi

  if [ -d ${RES_DIR}/baseline-${suffix}-${mem}g ]; then
    echo "${RES_DIR}/baseline-${suffix}-${mem}g exists!"
    exit 1
  fi

  if [ -d ${RES_DIR}/switch-${suffix}-${mem}g ]; then
    echo "${RES_DIR}/switch-${suffix}-${mem}g exists!"
    exit 1
  fi
done

for mem in "$@"; do
  bash physical-test.sh switch-${suffix}-${mem}g $mem
  bash physical-collect-res.sh switch-${suffix}-${mem}g

  bash physical-test.sh baseline-${suffix}-${mem}g $mem
  bash physical-collect-res.sh baseline-${suffix}-${mem}g
  # echo "${RES_DIR}/switch-${suffix}-${mem}g $mem"
  # echo "${RES_DIR}/baseline-${suffix}-${mem}g $mem"
done
