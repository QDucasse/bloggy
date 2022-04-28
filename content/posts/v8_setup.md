---
title: "V8 RISC-V setup"
date: "2022-04-24"
tags: [
    "riscv",
    "v8"
]
categories: [
    "Guide"
]
---

## Introduction

Let's create a root folder to hold the different elements of our build: the riscv toolchain, qemu and its images and the v8 sources. This folder will be called `v8_root` for the  rest of the guide.

## QEMU installation and setup

---

- *QEMU Installation:*

Clone the repository and checkout to the version 5.0:

```bash
$ git clone git@github.com:qemu/qemu.git
$ cd qemu
$ git checkout v5.0.0
```

Install the prerequisites

```bash
$ sudo apt-get install libglib2.0-dev libpixman-1-dev
```

Configure and install QEMU:

```bash
$ ./configure --target-list=riscv64-softmmu && make -j 4 # j can be changed to match the number of cores on your machine
$ sudo make install  # optional
```

---

- *Images download:*

Now that QEMU is installed, we need to download the Fedora images from the [fedora project site](https://dl.fedoraproject.org/pub/alt/risc-v/repo/virt-builder-images/images/). Each image needs its corresponding boot loader. U-Boot is an open-source multi-platform bootloader and can be found from the fedora project site as well.

```bash
$ cd v8_root
$ mkdir images && cd images
```

Note that two different versions are available: developer or minimal as well as a version number corresponding to the release date. Set the `VER` and `TYPE` accordingly:

```bash
$ export VER=20200108.n.0
$ export TYPE=MINIMAL
$ wget https://dl.fedoraproject.org/pub/alt/risc-v/repo/virt-builder-images/images/Fedora-${TYPE}-Rawhide-${VER}-sda.raw.xz
$ wget https://dl.fedoraproject.org/pub/alt/risc-v/repo/virt-builder-images/images/Fedora-${TYPE}-Rawhide-${VER}-fw_payload-uboot-qemu-virt-smode.elf
$ unxz -k Fedora-${TYPE}-Rawhide-${VER}-sda.raw.xz
```

---

- *QEMU launch:*

 Launching qemu with a given image boils down to this big command line:

```bash
$ qemu-system-riscv64 \
  -nographic \
  -machine virt \
  -smp 4 \
  -m 2G \
  -kernel Fedora-Developer-Rawhide-${VER}-fw_payload-uboot-qemu-virt-smode.elf \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -device virtio-rng-device,rng=rng0 \
  -device virtio-blk-device,drive=hd0 \
  -drive file=Fedora-Developer-Rawhide-${VER}-sda.raw,format=raw,id=hd0 \
  -device virtio-net-device,netdev=usernet \
  -netdev user,id=usernet,hostfwd=tcp::3333-:22
```

A launch script can be added to the image collection if you have to use several versions. A `launch.sh` file could look like:

```shell
# Quentin Ducasse, March 2022
#
# urls:
# https://wiki.qemu.org/Documentation/Platforms/RISCV
# https://picorio-doc.readthedocs.io/en/latest/software/v8.wiki/Cross-compiled-Build.html#run-qemu

# Arguments handling
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <version> <Developer|Minimal>" >&2
  exit 1
fi
version=$1
type=$2

qemu-system-riscv64 \
  -s \
  -nographic \
  -machine virt \
  -smp 4 \
  -m 2G \
  -kernel Fedora-${type}-Rawhide-${version}-fw_payload-uboot-qemu-virt-smode.elf \
  -bios none \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -device virtio-rng-device,rng=rng0 \
  -device virtio-blk-device,drive=hd0 \
  -drive file=Fedora-${type}-Rawhide-${version}-sda.raw,format=raw,id=hd0 \
  -device virtio-net-device,netdev=usernet \
  -netdev user,id=usernet,hostfwd=tcp::10000-:22

```

This script launches the image with for example:

```bash
$ ./launch.sh "20200108.n.0" "Minimal"  
```

---

- *QEMU runtime configuration:*

Once the image boot is complete, it will ask for a login/password that are `root`/`fedora_rocks!`. Once logged in, we now need to check for two things: enable root login over ssh with password and check the `glibc` version (as this will guide our toolchain setup).

*Setting up ssh:*

```bash
(qemu) $ nano /etc/ssh/sshd_config # use whatever text editor to add the next line into the file
...
PermitRootLogin=yes
...
(qemu) $ systemctl restart sshd.service # restart the ssh server
```

We can now use `ssh` and `scp` to our image using the port we defined in the launch script! It is defined with `hostfwd=tcp::10000-:22` which means that the port 10000 of the host machine (aka your machine) will be mapped to port 22 of our image (the default ssh port). An example of `scp` would be:

```bash
$ scp -r -P 10000 folder_to_transfer root@localhost:~  
```

*Checking for `glibc`:*

Run the command `ldd --version` to output the `glibc`version of the image:

```bash
(qemu) $ ldd --version
ldd (GNU libc) 2.30.9000
Copyright (C) 2020 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
Written by Roland McGrath and Ulrich Drepper.
```

In the case of the Fedora `Minimal-20200108.n.0` image, it uses `glibc 2.30.9000`.

> *Note:* To terminate the QEMU process pres `Ctrl-A` then `X`.

## RISC-V compilation toolchain

---

The `glibc` version we got from the previous step will help us configure the `riscv-compilation-toolchain`.

```bash
$ cd v8_root
$ git clone https://github.com/riscv/riscv-gnu-toolchain
$ cd riscv-gnu-toolchain
$ git submodule update --init --recursive
$ cd riscv-glibc
$ git checkout glibc-2.30.9000 # set glibc version (git tag will display all tags to look into)
```

Going back into the toolchain repository, we can now configure and compile the toolchain:

```bash
$ ./configure --prefix=/opt/riscv-glibc-2.30.9000 # I'd encourage you to do that if you have multiple toolchains
$ sudo make linux -j8 # setting linux will compile the glibc version (otherwise newlib!), adjust j8 as you prefer
```

You will need to add the path of the toolchain to the global path with:

```bash
$ export PATH="/opt/riscv-glibc-2.30.9000/bin:$PATH"
```

> *Note:* you might want to reiterate this export before building v8, this way (and by not adding it to bashrc) you can control which toolchain is used

## V8 setup

---

- *`depot_tools` installation:*

The V8 project uses Google's `depot_tools` to meta-manage git and the source code. Instructions are presented in the [V8 dev site](https://v8.dev/docs/source-code) but boils down to: `depot_tools` installation and repository sync.

```bash
$ git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
$ export PATH=$PATH:/path/to/depot_tools # or add to your bashrc to keep it in the path
$ gclient
Usage: gclient.py <command> [options]

Meta checkout dependency manager for Git.

Commands are:
  config   creates a .gclient file in the current directory
  diff     displays local diff for every dependencies
  fetch    fetches upstream commits for all modules
...
```

---

- *Get the sources:*

Getting the official V8 sources boils down to:

```bash
$ cd v8_root
$ fetch v8
```

To add the RISC-V branch (as it is not upstream):

```bash
$ git remote add riscv git@github.com:riscv/v8.git
$ git fetch riscv
$ git checkout riscv64
$ gclient sync --with_branch_heads --with_tags # gclient will look for depedencies itself
```

---

- *Configure build:*

Build dependencies are installed with the script `build/build-deps.sh`. We will need to change a line of the `build/toolchain/linux/BUILD.gn` file to make it compliant with our toolchain. It presents the gcc RISC-V toolchain in:

```gn
gcc_toolchain("riscv64") {
  toolprefix = "riscv64-linux-gnu"
  ...
```

However, our toolchain uses the `riscv64-unknown-linux-gnu` prefix. You can double check this and use yours by doing:

```bash
$ ls /opt/riscv-glibc-2.30.9000
bin/  include/  lib/  libexec/  riscv64-unknown-linux-gnu/  share/  sysroot/
$ ls /opt/riscv-glibc-2.30.9000/bin
riscv64-unknown-linux-gnu-addr2line  riscv64-unknown-linux-gnu-g++        riscv64-unknown-linux-gnu-gcov-dump         
riscv64-unknown-linux-gnu-ld.bfd     riscv64-unknown-linux-gnu-run        riscv64-unknown-linux-gnu-ar
riscv64-unknown-linux-gnu-gcc        riscv64-unknown-linux-gnu-gcov-tool  riscv64-unknown-linux-gnu-lto-dump  
riscv64-unknown-linux-gnu-size       riscv64-unknown-linux-gnu-as         riscv64-unknown-linux-gnu-gcc-11.1.0    
riscv64-unknown-linux-gnu-gdb        riscv64-unknown-linux-gnu-nm         ...
```

We can replace the line in the toolchain with:

```bash
sed -i 's/riscv64-linux-gnu/riscv64-unknown-linux-gnu/g' build/toolchain/linux/BUILD.gn
```

---

- *Build V8:*

We can now build V8 with:

```bash
$ gn gen out/riscv64.native.debug --args='is_component_build=false is_debug=true target_cpu="riscv64" v8_target_cpu="riscv64" use_goma=false goma_dir="None" treat_warnings_as_errors=false'
$ ninja -C out/riscv64.native.debug -j8 # tune j as needed
```

**IF THE BUILD FAILS WITH** `#error Please add support for your architecture in build/build_config.h`, we need to generate d8 only with:

```bash
$ cd out/riscv64.native.debug
$ gn gen .
$ ninja d8 -j8 # tune j as needed
```
