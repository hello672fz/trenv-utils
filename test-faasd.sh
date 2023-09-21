#!/bin/bash
set -e

# activate some kernel module
echo "insert needed kernel module..."
needed_modules=(overlay llc stp bridge xt_mark xt_comment xt_MASQUERADE xt_conntrack nf_conntrack nf_conntrack_netlink)
for mod in ${needed_modules[@]}; do
  modprobe $mod
done


echo "start containerd and download container images..."
containerd -l debug &> /tmp/containerd.log &
sleep 5

# download images
apps=(h-hello-world h-memory pyaes image-processing)
for app in ${apps[@]}; do
  echo "start download $app ..."
  ctr image pull docker.io/jialianghuang/${app}:latest
done

# start faasd
echo "start generate and convert checkpoint image for functions..."
faasd install
cd /var/lib/faasd
secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
  --pull-policy no &> /tmp/faasd.log &
faasd_pid=$!
sleep 1

cat /var/lib/faasd/secrets/basic-auth-password | faas-cli login -u admin --password-stdin \
  -g http://127.0.0.1:8081 

cd /root
faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "h-hello*"
sleep 1
curl http://127.0.0.1:8081/function/h-hello-world-1
faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "h-mem*"
sleep 1
curl -X POST http://127.0.0.1:8081/function/h-memory-1 -d '{"size": 134217728}'

faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "pyaes"
sleep 1
curl -X POST http://127.0.0.1:8081/function/pyaes-1 -d '{"length_of_message": 2000, "num_of_iterations": 200}'
faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "image*"
sleep 1
curl http://127.0.0.1:8081/function/image-processing-1

# generate and convert checkpoint
faasd checkpoint h-hello-world-1 h-memory-1 pyaes-1 image-processing-1

# clear container and restart faasd
kill $faasd_pid
ctr -n openfaas-fn c rm h-hello-world-1
ctr -n openfaas-fn c rm h-memory-1
ctr -n openfaas-fn c rm pyaes-1
ctr -n openfaas-fn c rm image-processing-1

echo "start launch serverless app with the help of C/R..."
sleep 2
secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
  --pull-policy no &> /tmp/faasd.log &
sleep 1

faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "h-hello*"
curl http://127.0.0.1:8081/function/h-hello-world-1
faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "h-mem*"
curl -X POST http://127.0.0.1:8081/function/h-memory-1 -d '{"size": 12345678}'
faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "pyaes*"
curl -X POST http://127.0.0.1:8081/function/pyaes-1 -d '{"length_of_message": 4000, "num_of_iterations": 120}'
faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "image*"
curl http://127.0.0.1:8081/function/image-processing-1
