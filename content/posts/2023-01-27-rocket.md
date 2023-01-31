---
title: "Rocket chip building"
date: "2023-01-27"
tags: [
    "riscv",
    "rocket"
]
categories: [
    "Guide"
]
---

## Installation and simulation of the Rocket processor

Rocket is a fully-featured RISC-V processor capable of running Linux. Here, we will install the [core](https://github.com/chipsalliance/rocket-chip) and its [toolchain](https://github.com/chipsalliance/rocket-tools).

### Setup

Since we will need two different repositories, let's setup a root directory `rocket-root` and clone both of the projects:

```bash
$ mkdir rocket-root && cd rocket-root
$ git clone git@github.com:chipsalliance/rocket-chip.git
$ git clone git@github.com:chipsalliance/rocket-tools.git
$ export ROCKET_ROOT="$HOME/path/to/rocket-root"
```

The known checkout hash for the `rocket-tools` repository is noted in the file `riscv-tools.hash`. At the time of writing, the latest Rocket release is `1.6` so let's checkout:

```bash
$ cd $ROCKET_ROOT/rocket-chip && git checkout v1.5
$ cd $ROCKET_ROOT/rocket-tools && git checkout `cat $ROCKET_ROOT/rocket-chip/riscv-tools.hash`
```

> Note: The `v1.5` and `1.6` use the same `riscv-tools` version

### Rocket tools installation

Thanks to Pascal for its [gist](https://gist.github.com/pcotret/11afe52a1834172981c1e371b8bdcf03), we will break it down in the next section.
We first start by building the tools. The `rocket-tools` repository is a collection of the needed tools that support the Rocket chip generator such as `spike` the ISA simulator, `riscv-tests` the ISA-level unit tests, `riscv-opcodes` the enumeration of all RISC-V opcodes executable by the simulator and `riscv-pk` which contains both `bbl` the boot loader for Linux and `pk` a proxy kernel.

First of all, the repository depends on the following Ubuntu packages:

```bash
$ sudo apt-get update
$ sudo apt-get install autoconf automake autotools-dev curl libmpc-dev libmpfr-dev libgmp-dev libusb-1.0-0-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev device-tree-compiler pkg-config libexpat-dev libfl-dev
```

Once the dependencies are installed, we need to redirect some of the git submodules to their `https` counterparts:

```bash
$ git submodule set-url fsf-binutils-gdb https://sourceware.org/git/binutils-gdb.git
$ git submodule sync
```

And the qemu repositories:
```bash
$ git submodule set-url riscv-qemu https://github.com/riscv/riscv-qemu.git
$ git submodule sync
$ git submodule update --init riscv-qemu
$ git submodule set-url roms/vgabios https://git.qemu.org/git/vgabios.git
$ git submodule set-url roms/seabios https://git.qemu.org/git/seabios.git
$ git submodule set-url roms/SLOF https://git.qemu.org/git/SLOF.git
$ git submodule set-url roms/ipxe https://git.qemu.org/git/ipxe.git
$ git submodule set-url roms/openbios https://git.qemu.org/git/openbios.git
$ git submodule set-url roms/openhackware https://git.qemu.org/git/openhackware.git
$ git submodule set-url roms/qemu-palcode https://github.com/rth7680/qemu-palcode.git
$ git submodule set-url roms/sgabios https://git.qemu.org/git/sgabios.git
$ git submodule set-url pixman https://gitlab.freedesktop.org/pixman/pixman 
$ git submodule set-url dtc https://git.qemu.org/git/dtc.git  
$ git submodule set-url roms/u-boot https://git.qemu.org/git/u-boot.git
$ git submodule sync
```

Finally, the installation to the path of your choice (`/opt/riscv-rocket`) here:
```bash
$ cd $ROCKET_ROOT
$ git submodule update --init --recursive --progress
$ export RISCV=/opt/rocket-riscv
$ ./build.sh
```

The toolchain is now installed!

### Environment Setup for the Rocket Chip

With the tools installed, the missing element is the  Scala installation. We first need [coursier](https://github.com/coursier/coursier), the Scala artifact installer along with a Java sdk. First check your Java installation:
```bash
$ sudo apt-get install default-jdk	
$ java -version
```

Then install Coursier:
```bash
$ cd $ROCKET_ROOT
$ wget https://github.com/coursier/coursier/releases/latest/download/coursier.jar
$ java -jar coursier.jar setup
```

We can finally initialize the Rocket chip:
```bash
$ cd $ROCKET_ROOT/rocket-chip
$ git submodule update --init
```

### Building the simulator

We can now build either the C simulator:
```bash
$ cd emulator # C sim
$ make
```

To run assembly and benchmarks tests (adding `-debug` generates the waveform), using `N` as the number of cores:
```bash
$ make -jN run-asm-tests
$ make -jN run-bmark-tests
$ make -jN run-asm-tests-debug # With waveforms
```
