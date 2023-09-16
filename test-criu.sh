#!/bin/bash
set -e
source /root/app/faas/bin/activate
rm -rf /root/images

# dump app 1
cd /root/h-memory
setsid python index.py < /dev/null &> /dev/null &
target_pid=$!
sleep 0.5
curl -X POST http://localhost:5000 -d '{"size": 134217728}'
mkdir -p /root/images/h-memory
criu dump -t $target_pid -D /root/images/h-memory -o dump.log -v4

# dump app 2
cd /root/h-hello-world
setsid python index.py < /dev/null &> /dev/null &
target_pid=$!
sleep 0.5
curl http://localhost:5000
mkdir -p /root/images/h-hello-world
criu dump -t $target_pid -D /root/images/h-hello-world -o dump.log -v4

# convert image
sleep 1
criu convert -D /root/images -v4 --dax-device /dev/dax0.0

# resotre
sleep 0.5
mkdir -p /run/criu-restore
criu restore -d -D /root/images/h-memory/ -W /run/criu-restore -v4 -o restore.log

curl -X POST http://localhost:5000 -d '{"size": 512000}'
