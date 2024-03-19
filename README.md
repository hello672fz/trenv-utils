# Test Environment Preparation

## Software

First please make sure you are using our [kernel](https://github.com/switch-container/linux).

You need to download following code and compile yourself, mostly they are written in c/c++ and go. Go version has to >= 1.20.

- [faasd](https://github.com/switch-container/faasd):
  
  - on switch branch: `make local && make install`
    
- [faas-cli](https://github.com/switch-container/faas-cli):
  
  - `make local-install`
    
- [criu](https://github.com/switch-container/criu):
  
  - on switch branch: `make -j32 install-criu && cp criu/criu /root/downloads/switch-criu`
    
  - on v3.18: `make -j32 install-criu && cp criu/criu /root/downloads/raw-criu`
    
- [containerd](https://github.com/switch-container/containerd)
  
  - on switch branch: `BUILDTAGS=no_btrfs make && make install`
    
- [runc](https://github.com/switch-container/runc)
  
  - on switch branch: `make runc && make install`
    
- [faasd-testdriver](https://github.com/switch-container/faasd-testdriver)
  
  - copy this dir to `/root/test/`
    
- [rdma-server](https://github.com/switch-container/rdma-server)
  
  - `make && cp pseudo-mm-rdma-server /root/test`
    

## Scripts

Three scripts in util repo is needed to run test:

- `test.sh`
  
  - used to run different test, e.g., azure trace test or functional test
- `test-common.sh`
  
  - define some common shell functions
- `machine-prepare.sh`
  
  - need to run **only once** for each system boot

However, `machine-prepare.sh` only start necessary daemon, insert kernel modules, configure softroce (rxe), generate checkpoints and mm-template (called `pseudo_mm` in kernel code). It will not install or compile software. So you need to compile software at first and put it in the right place.

After boot, run:

- `bash machine-prepare.sh --mem-pool rdma --nic eth0` for rdma based test
  
- `bash machine-prepare.sh --mem-pool dax --dax-dev /dev/dax0.0` for cxl based test
  

Then start test, run:

- `bash test.sh --mem 64` for our method
  
- `base test.sh --mem 64 --gc 10 --baseline` for containerd / docker container
  
- `base test.sh --mem 64 --gc 10 --baseline --start-method criu` for starting container with CRIU
