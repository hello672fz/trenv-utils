#!/bin/bash
# run inside multipass vm

set -e

cd ~/function

http_proxy=http://172.17.0.1:7890 https_proxy=http://172.17.0.1:7890 faas build -f stack.yml --build-option net
http_proxy=http://172.17.0.1:7890 https_proxy=http://172.17.0.1:7890 faas push -f ./stack.yml
bash build-pkgs.sh /home/ubuntu/function/build
rm -rf ~/multipass-shared/pkgs
mv pkgs ~/multipass-shared
yes | docker system prune

cd ~/qemu_linux
rm -rf output work
rm ~/multipass-shared/rootfs

bash mkrootfs.sh
cp output/rootfs ~/multipass-shared/
# http_proxy=http://172.17.0.1:7890 https_proxy=http://172.17.0.1:7890 faas build -f stack.yml
