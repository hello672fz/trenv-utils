#!/bin/bash
set -e

if [ -f /root/criu.kdat ]; then
  echo "copying criu.kdat..."
  cp /root/criu.kdat /run
fi

rm -f /usr/bin/criu
cp /root/criu  /tmp
ln -s /tmp/criu /usr/bin/criu

echo "start containerd and download container images..."
containerd -l debug &> /tmp/containerd.log &
sleep 5

# download images
apps=(h-hello-world h-memory pyaes image-processing video-processing \
  image-recognition chameleon dynamic-html)
for app in ${apps[@]}; do
  echo "start download $app ..."
  ctr image pull docker.io/jialianghuang/${app}:latest
  ctr -n openfaas-fn c rm ${app}-1 || true
  ctr -n openfaas-fn c rm ${app} || true
done

rm -rf /var/lib/faasd/checkpoints
mkdir -p /var/lib/faasd/checkpoints
mount -t tmpfs tmpfs /var/lib/faasd/checkpoints -o size=4G

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
curl http://127.0.0.1:8081/function/h-hello-world

faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "h-mem*"
sleep 1
curl -X POST http://127.0.0.1:8081/function/h-memory -d '{"size": 134217728}'

faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "pyaes"
sleep 1
curl -X POST http://127.0.0.1:8081/function/pyaes -d '{"length_of_message": 2000, "num_of_iterations": 200}'

faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "image-pro*"
sleep 1
curl http://127.0.0.1:8081/function/image-processing

faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "image-rec*"
sleep 3
curl http://127.0.0.1:8081/function/image-recognition

faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "video*"
sleep 1
curl http://127.0.0.1:8081/function/video-processing

faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "cham*"
sleep 1
curl -X POST -d '{"num_of_rows": 1000, "num_of_cols": 1000}' http://127.0.0.1:8081/function/chameleon &> chameleon.output

faas-cli deploy --update=false -f /root/stack.yml -g http://127.0.0.1:8081 --filter "dyn*"
sleep 1
curl -X POST -d '{"username": "Tsinghua", "random_len": 1000}' http://127.0.0.1:8081/function/dynamic-html &> dynamic-html.output

# generate and convert checkpoint
# NOTE by huang-jl: the first time criu running will spent a lot of time querying kernel capabilities
# (about 2 mins) so this will spent a lot of time
# Maybe a solution is copy criu.kdat into /run/ beforehand 
faasd checkpoint h-hello-world h-memory pyaes image-processing image-recognition video-processing chameleon dynamic-html
cp /run/criu.kdat /root

# clear container and restart faasd
kill $faasd_pid
for app in ${apps[@]}; do
  ctr -n openfaas-fn c rm $app
done

echo "start launch serverless app with the help of C/R..."
sleep 1
secret_mount_path=/var/lib/faasd/secrets basic_auth=true faasd provider \
  --pull-policy no &> /tmp/faasd.log &
sleep 2

# register new container
faas-cli register -f /root/stack.yml -g http://127.0.0.1:8081
sleep 2

curl http://127.0.0.1:8081/invoke/h-hello-world
# belows are all switch by default
for ((i = 1; i <= 3; i++)); do
  curl -X POST http://127.0.0.1:8081/invoke/h-memory -d '{"size": 12345678}'
  
  curl -X POST http://127.0.0.1:8081/invoke/pyaes -d '{"length_of_message": 4000, "num_of_iterations": 120}'
  
  curl http://127.0.0.1:8081/invoke/image-processing
  
  curl http://127.0.0.1:8081/invoke/image-recognition
  
  curl http://127.0.0.1:8081/invoke/video-processing
  
  curl -X POST -d '{"num_of_rows": 500, "num_of_cols": 1500}' http://127.0.0.1:8081/invoke/chameleon &> chameleon-${i}-cr.log
  
  curl -X POST -d '{"username": "Peking", "random_len": 1554}' http://127.0.0.1:8081/invoke/dynamic-html &> dynamic-html-${i}-cr.log
done

curl http://127.0.0.1:8081/system/metrics &> metrics.output

