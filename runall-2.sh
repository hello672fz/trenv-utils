#!/bin/bash

RES_DIR=/root/test/result
curr_dir=$(pwd)

# cd /root/test/faasd-testdriver
# echo "generating w1 trace..."
# python gen_trace.py -w 1
# cd $curr_dir
# # since different criu version containers different kdat cache
# # so we'd better run switch for all and then change to criu for efficiency
# 
# bash physical-test.sh baseline-w1 64 1
# bash physical-collect-res.sh baseline-w1
# 
# bash physical-test.sh criu-w1 64 1
# bash physical-collect-res.sh criu-w1
# 
# bash physical-test.sh switch-w1 64 1
# bash physical-collect-res.sh switch-w1

cd /root/test/faasd-testdriver
echo "generating w2 trace..."
python gen_trace.py -w 2
cd $curr_dir

bash physical-test.sh baseline-w2 32 3
bash physical-collect-res.sh baseline-w2

bash physical-test.sh criu-w2 32 3
bash physical-collect-res.sh criu-w2

bash physical-test.sh switch-w2 32 3
bash physical-collect-res.sh switch-w2
