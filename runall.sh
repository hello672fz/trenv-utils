#!/bin/bash

RES_DIR=/root/test/result
curr_dir=$(pwd)

azure_mems=(48)
ali_mems=(48)

criu_azure_mems=(48)
criu_ali_mems=(48)


# check azure trace result
for mem in ${azure_mems[@]}; do
  echo "azure mems: $mem"
  if [ -d ${RES_DIR}/baseline-azure-${mem}g ]; then
    echo "${RES_DIR}/baseline-azure-${mem}g exists!"
    exit 1
  fi

  if [ -d ${RES_DIR}/switch-azure-${mem}g ]; then
    echo "${RES_DIR}/switch-azure-${mem}g exists!"
    exit 1
  fi
done

for mem in ${criu_azure_mems[@]}; do
  echo "criu azure mems: $mem"
  if [ -d ${RES_DIR}/criu-azure-${mem}g ]; then
    echo "${RES_DIR}/criu-azure-${mem}g exists!"
    exit 1
  fi
done
# check ali trace result
for mem in ${ali_mems[@]}; do
  echo "ali mems: $mem"
  if [ -d ${RES_DIR}/baseline-ali-${mem}g ]; then
    echo "${RES_DIR}/baseline-ali-${mem}g exists!"
    exit 1
  fi

  if [ -d ${RES_DIR}/switch-ali-${mem}g ]; then
    echo "${RES_DIR}/switch-ali-${mem}g exists!"
    exit 1
  fi
done

for mem in ${criu_ali_mems[@]}; do
  echo "criu ali mems: $mem"
  if [ -d ${RES_DIR}/criu-ali-${mem}g ]; then
    echo "${RES_DIR}/criu-ali-${mem}g exists!"
    exit 1
  fi
done


cd /root/test/faasd-testdriver
echo "generating azure trace..."
python gen_trace.py -w azure --dataset /root/downloads/azurefunction-dataset2019
cd $curr_dir
# since different criu version containers different kdat cache
# so we'd better run switch for all and then change to criu for efficiency
for mem in ${azure_mems[@]}; do
  bash physical-test.sh switch-azure-${mem}g $mem
  bash physical-collect-res.sh switch-azure-${mem}g

  bash physical-test.sh baseline-azure-${mem}g $mem
  bash physical-collect-res.sh baseline-azure-${mem}g
done

cd /root/test/faasd-testdriver
echo "generating ali trace..."
python gen_trace.py -w ali --dataset /root/downloads/data_training/dataSet_3
cd $curr_dir
for mem in ${ali_mems[@]}; do
  bash physical-test.sh switch-ali-${mem}g $mem
  bash physical-collect-res.sh switch-ali-${mem}g

  bash physical-test.sh baseline-ali-${mem}g $mem
  bash physical-collect-res.sh baseline-ali-${mem}g
done


# then we test criu
cd /root/test/faasd-testdriver
echo "generating azure trace..."
python gen_trace.py -w azure --dataset /root/downloads/azurefunction-dataset2019
cd $curr_dir
# since different criu version containers different kdat cache
# so we'd better run switch for all and then change to criu for efficiency
for mem in ${criu_azure_mems[@]}; do
  bash physical-test.sh criu-azure-${mem}g $mem
  bash physical-collect-res.sh criu-azure-${mem}g
done

cd /root/test/faasd-testdriver
echo "generating ali trace..."
python gen_trace.py -w ali --dataset /root/downloads/data_training/dataSet_3
cd $curr_dir
for mem in ${criu_ali_mems[@]}; do
  bash physical-test.sh criu-ali-${mem}g $mem
  bash physical-collect-res.sh criu-ali-${mem}g
done

sync
sync
sync

sleep 20

reboot
