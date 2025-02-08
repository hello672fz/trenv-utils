#!/bin/bash
set -e

# Example
# baseline test:
# --baseline --gc 10 --start-method cold
# criu test:
# --baseline --start-method criu --gc 10

MEM=4  # default 4G
IS_BASELINE=0 # default not baseline
START_METHOD="cold" # default cold start
GC_CRITERION=10 # default gc is 10 min
NO_BG_TASK=0  # default enable bg task
TEST_NAME=""
FUNCTIONAL_ITER=0
NO_TEST=0
NO_REUSE=0
IDLE_NUM=-1

# import test-common.sh
THIS=`readlink -f "${BASH_SOURCE[0]}" 2>/dev/null||echo $0`
DIR=`dirname "${THIS}"`
. "$DIR/test-common.sh"

function start_test {
  echo "start normal test"
  cd $WORKDIR
  echo $WORKDIR
  # register new container
  faas-cli register -f $WORKDIR/stack.yml -g http://127.0.0.1:8081
  sleep 2

  source /root/venv/faasd-test/bin/activate
  python $WORKDIR/main.py
  echo ""
   
  curl http://127.0.0.1:8081/system/metrics
  echo ""
}


function functional_test() {
  local iter=$1
  echo "start functional test..."

  cd $WORKDIR
  # register new container
  faas-cli register -f $WORKDIR/stack.yml -g http://127.0.0.1:8081
  sleep 2

  curl http://127.0.0.1:8081/invoke/h-hello-world
  echo ""

  curl http://127.0.0.1:8081/system/metrics
  echo ""
}

# start_test
functional_test

