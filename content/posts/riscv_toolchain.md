---
title: "RISC-V toolchain with custom glibc"
date: "2022-03-23"
tags: [
    "riscv",
    "glibc"
]
categories: [
    "Guide"
]
---


## Linking against your own `glibc`

The `glibc` is what defines the base C libraries needed by a program.

```shell
# Quentin Ducasse, March 2022
#   taken from Claas Heuer, August 2015, https://gist.github.com/cheuerde/7229f304856e59ce183a
#
# urls:
# http://stackoverflow.com/questions/847179/multiple-glibc-libraries-on-a-single-host
# http://www.gnu.org/software/libc/download.html

# Arguments handling
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <glibc_version>" >&2
  exit 1
fi
libc_version=$1

# create a temp folder to build glibc
cd $HOME
mkdir glibc_update
cd glibc_update

# get glibc version
wget https://ftp.gnu.org/gnu/glibc/glibc-${libc_version}.tar.gz
tar -xf glibc-${libc_version}.tar.gz

# configure and set the installation path
cd glibc-${libc_version}
mkdir build
cd build
../configure --prefix=/opt/glibc-${libc_version} --enable-cet

# compile
make -j6
sudo make install
```

You can then link with this version with flags:

```bash
$ export GLIBC_VERSION="2.30"
$ gcc main.o -o myapp ... \
	-Wl,--rpath=/opt/glibc-${GLIBC_VERSION} \
	-Wl,--dynamic-linker=/opt/glibc-${GLIBC_VERSION}/lib/ld-${GLIBC_VERSION}.so
```

## Cross-compiling

Before any action on the toolchain, check which version of `glibc` you will need on the target architecture. This is available through `ldd --version`.



In my case, working on RISC-V, I will look at **(1)** the **QEMU image** (`Fedora-Rawhide-Minimal-20200108.n.0`) **(2) Actual hardware** (Beagle-V with `Fedora-riscv64-jh7100-developer-xfce-Rawhide-20211226-214100.n.0`)

```bash
$ ldd --version # qemu
	ldd (GNU libc) 2.30.9000
	Copyright (C) 2020 Free Software Foundation, Inc.
	This is free software; see the source for copying conditions.  There is NO
	warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
	Written by Roland McGrath and Ulrich Drepper.

```

```bash
$ ldd --version # beagle-v
	ldd (GNU libc) 2.32
	Copyright (C) 2020 Free Software Foundation, Inc.
	This is free software; see the source for copying conditions.  There is NO
	warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
	Written by Roland McGrath and Ulrich Drepper.
```



Now that we have these information, we need to compile the toolchain using the correct `glibc` version. We will go with `glibc-2.30.9000` here.

```bash
$ git clone https://github.com/riscv/riscv-gnu-toolchain
$ cd riscv-gnu-toolchain
$ git submodule update --init --recursive
```

We need to change the `glibc` version:

```bash
$ cd riscv-glibc
$ git checkout glibc-2.30.9000
```

Now compile the toolchain as usual:

```bash
$ ./configure --prefix=/opt/riscv-glibc-2.30.9000
$ sudo make linux
```

> *Note: The option `--enable-multilib` that allows cross-compiler support for **both** 32-bit and 64-bit is not available as `glibc-2.30` does not support rv32 yet*
