---
title: "Running raw binary on Rocket's emulator"
date: "2023-02-07"
tags: [
    "riscv",
    "rocket"
]
categories: [
    "Exploration"
]
---

## Gigue presentation and binary generation

My goal is to run raw binary code on top of the Rocket emulator. The code itself is the output of my JIT code generator [Gigue](https://github.com/QDucasse/gigue). It generates random JIT methods and Polymorphic Inline Caches (machine code switch before different methods). It generates raw binary instructions as the succession of the interpretation loop, a filler and the JIT code.

The generated code is customizable by defining: 
- the start address of the interpretation loop and JIT code
- the number of JIT elements (methods + PICs)
- the method/PICs ratio 
- the max call depth (nested calls) of a method
- the max call number of a method
- the max method size
- etc.

The code is tested and simulated with [`capstone`](https://github.com/capstone-engine/capstone) and [`unicorn`](https://github.com/unicorn-engine/unicorn).

Gigue uses `pipenv` and can be installed following:

```bash
$ git clone git@github.com:QDucasse/gigue.git
$ cd gigue
$ pipenv install --dev  # dev for capstone/unicorn
$ pipenv shell
```

A lot of command line arguments help customize the generated code. The ones we need are: 
- `-I` or `--intaddr` the address of the interpretation loop
- `-J` or `--jitaddr` the address of the JIT code
- `-N` or `--nbelt` the number of JIT elements
- `-R` or `--picratio` the methods/PICs ratio (0 means no PICs 1 means only PICs)
- `-O` or `--out` the name of the output binary file

For now, let's use the defaults ones and generate the code using:
```bash
$ python -m gigue
```

The resulting binary is generated in `bin/out.bin`!

## First run of the binary

The resulting `bin/out.bin` is raw data but we can still look at it using `objdump`:
```bash
$ riscv64-unknown-elf-objdump \
    --adjust-vma=0x1000 \
    -m riscv \
    -b binary \
    -D out.bin > out.dis
$ head out.dis
Disassembly of section .data:

0000000000001000 <.data>:
    1000:	fd410113          	addi	sp,sp,-44
    1004:	00812023          	sw	s0,0(sp)
    1008:	00912223          	sw	s1,4(sp)
    100c:	01212423          	sw	s2,8(sp)
    1010:	01312623          	sw	s3,12(sp)
    1014:	01412823          	sw	s4,16(sp)
    1018:	01512a23          	sw	s5,20(sp)
    101c:	01612c23          	sw	s6,24(sp)
    1020:	01712e23          	sw	s7,28(sp)
    1024:	03812023          	sw	s8,32(sp)
    1028:	03912223          	sw	s9,36(sp)
    102c:	02112423          	sw	ra,40(sp)
    1030:	00005097          	auipc	ra,0x5
    1034:	00c080e7          	jalr	12(ra) # 0x603c
    1038:	00009097          	auipc	ra,0x9
    103c:	044080e7          	jalr	68(ra) # 0xa07c
    1040:	00006097          	auipc	ra,0x6
    1044:	26c080e7          	jalr	620(ra) # 0x72ac
    1048:	00006097          	auipc	ra,0x6
    104c:	39c080e7          	jalr	924(ra) # 0x73e4
    1050:	00007097          	auipc	ra,0x7
    1054:	ae4080e7          	jalr	-1308(ra) # 0x7b34
    1058:	00004097          	auipc	ra,0x4
```

As you can see the whole code is wrapped in the `.data` section, starting at the address specified with `--adjust-vma`. Rocket expects an ELF file to run on top of its emulator so let's see how we can wrap our file.

We will use `objcopy` to use a raw binary input and output an ELF64 little-endian RISC-V file.
```bash
$ riscv64-unknown-elf-objcopy \
    -I binary \
    -O elf64-littleriscv \
    -B riscv \
    out.bin out.elf
```

Reading the file now with `readelf` shows us:
```bash
$ riscv64-unknown-elf-readelf -hS out.o
LF Header:
  Magic:   7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00 
  Class:                             ELF64
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              REL (Relocatable file)
  Machine:                           RISC-V
  Version:                           0x1
  Entry point address:               0x0
  Start of program headers:          0 (bytes into file)
  Start of section headers:          41528 (bytes into file)
  Flags:                             0x0
  Size of this header:               64 (bytes)
  Size of program headers:           0 (bytes)
  Number of program headers:         0
  Size of section headers:           64 (bytes)
  Number of section headers:         5
  Section header string table index: 4

Section Headers:
  [Nr] Name              Type             Address           Offset
       Size              EntSize          Flags  Link  Info  Align
  [ 0]                   NULL             0000000000000000  00000000
       0000000000000000  0000000000000000           0     0     0
  [ 1] .data             PROGBITS         0000000000000000  00000040
       000000000000a12c  0000000000000000  WA       0     0     1
  [ 2] .symtab           SYMTAB           0000000000000000  0000a170
       0000000000000060  0000000000000018           3     1     8
  [ 3] .strtab           STRTAB           0000000000000000  0000a1d0
       0000000000000040  0000000000000000           0     0     1
  [ 4] .shstrtab         STRTAB           0000000000000000  0000a210
       0000000000000021  0000000000000000           0     0     1
Key to Flags:
  W (write), A (alloc), X (execute), M (merge), S (strings), I (info),
  L (link order), O (extra OS processing required), G (group), T (TLS),
  C (compressed), x (unknown), o (OS specific), E (exclude),
  D (mbind), p (processor specific)
```
> Note: `-h` for the header, `-S` for the sections!

The file here has no Flags (where we would expect a presentation of the ABI) and is Relocatable and not Executable. If we try to feed it to Rocket's emulator in its current state, it fails with the following error:
```bash
$ ./emulator-freechips.rocketchip.system-freechips.rocketchip.system.DefaultConfig \
    +max-cycles=100000000 \
    +verbose \
    path/to/out.o
... ../fesvr/elfloader.cc:35: std::map<std::__cxx11::basic_string<char>, long unsigned int> load_elf(const char*, memif_t*, reg_t*): Assertion `IS_ELF_EXEC(*eh64)' failed.

```

We can try to hack our way into the ELF and make it executable with `elfedit`:
```bash
$ riscv64-unknown-elf-elfedit out.o --input-type=rel --output-type=exec
$ riscv64-unknown-elf-readelf -hS out.o | grep "Type:"
  Type:            EXEC (Executable file)
```

Running it now launches the emulator for a bit, fails with an error and loops over `NULL` values:
```bash
./emulator-freechips.rocketchip.system-freechips.rocketchip.system.DefaultConfig \
    +max-cycles=100000000 \
    +verbose \
    path/to/out.o
...
C0:        240 [1] pc=[0000000000000828] W[r 8=0000000000000000][1] R[r 8=0000000000000002] R[r 0=0000000000000000] inst=[00147413] DASM(00147413)
C0:        241 [1] pc=[000000000000082c] W[r 0=0000000000000000][0] R[r 8=0000000000000000] R[r 0=0000000000000000] inst=[00040863] DASM(00040863)
C0:        245 [1] pc=[000000000000083c] W[r 8=0000000000000000][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[f1402473] DASM(f1402473)
C0:        265 [1] pc=[0000000000000840] W[r 0=0000000000000000][0] R[r 0=0000000000000000] R[r 8=0000000000000000] inst=[10802423] DASM(10802423)
C0:        266 [1] pc=[0000000000000844] W[r 8=e291ba58c157406e][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[7b202473] DASM(7b202473)
C0:        267 [1] pc=[0000000000000848] W[r 0=0000000000000000][0] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[7b200073] DASM(7b200073)
C0:        286 [1] pc=[0000000000010058] W[r 0=000000000001005a][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[0000bff5] DASM(0000bff5)
C0:        288 [1] pc=[0000000000010054] W[r 0=0000000000000000][0] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[10500073] DASM(10500073)
warning: tohost and fromhost symbols not in ELF; can't communicate with target
C0:        291 [0] pc=[0000000000010058] W[r 0=0000000000000000][0] R[r31=0000000000000000] R[r 0=0000000000000000] inst=[0000bff5] DASM(0000bff5)
C0:        296 [1] pc=[0000000000000800] W[r 0=0000000000000804][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[00c0006f] DASM(00c0006f)
C0:        297 [1] pc=[000000000000080c] W[r 0=0000000000000000][0] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[0ff0000f] DASM(0ff0000f)
C0:        298 [1] pc=[0000000000000810] W[r 0=e291ba58c157406e][1] R[r 8=e291ba58c157406e] R[r 0=0000000000000000] inst=[7b241073] DASM(7b241073)
C0:        303 [1] pc=[0000000000000814] W[r 8=0000000000000000][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[f1402473] DASM(f1402473)
C0:        306 [1] pc=[0000000000000818] W[r 0=0000000000000000][0] R[r 0=0000000000000000] R[r 8=0000000000000000] inst=[10802023] DASM(10802023)
C0:        312 [1] pc=[000000000000081c] W[r 8=0000000000000000][0] R[r 8=0000000000000000] R[r 0=0000000000000000] inst=[40044403] DASM(40044403)
C0:        320 [1] pc=[0000000000000820] W[r 8=0000000000000000][1] R[r 8=0000000000000000] R[r 0=0000000000000000] inst=[00347413] DASM(00347413)
...
```

The `tohost` and `fromhost` routines are not setup in our executable...


## Linking our raw binary

With the previous issue in mind, we will try to follow the way the benchmark tests link and wrap binaries! We need to collectivize several files: the [`common`](https://github.com/riscv-software-src/riscv-tests/tree/19bfdab48c2a6da4a2c67d5779757da7b073811d/benchmarks/common) directory (that contains `crt.S` the initialization script, `syscalls.c` the system calls wrapper, `utils.h` some helpers and `test.ld` the loader script) as well as the [`encoding.h`](https://github.com/riscv/riscv-test-env/blob/68cad7baf3ed0a4553fffd14726d24519ee1296a/encoding.h) defines instructions/CSRs (taken from the `riscv-test-env` repository). 

Everything is stored in the `resources` directory:
```bash
$ tree resources
resources
└── common
    ├── crt.S
    ├── encoding.h
    ├── syscalls.c
    ├── test.ld
    └── util.h

1 directory, 5 files
```

Running `make` in the Gigue root repository should compile each file and link them together! However, since we are getting the raw binary file and forcing into an ELF file, the linker fails with:
```bash
$ make
/opt/riscv-rocket/bin/riscv64-unknown-elf-objcopy -I binary -O elf64-littleriscv -B riscv --rename-section .data=.text bin/out.bin bin/out.o
/opt/riscv-rocket/bin/riscv64-unknown-elf-gcc -static -nostdlib -nostartfiles -lm -lgcc -T resources/common/test.ld bin/out.o bin/syscalls.o bin/crt.o -o bin/out
/opt/riscv-rocket/lib/gcc/riscv64-unknown-elf/7.2.0/../../../../riscv64-unknown-elf/bin/ld: bin/syscalls.o: can't link double-float modules with soft-float modules
/opt/riscv-rocket/lib/gcc/riscv64-unknown-elf/7.2.0/../../../../riscv64-unknown-elf/bin/ld: failed to merge target specific data of file bin/syscalls.o
/opt/riscv-rocket/lib/gcc/riscv64-unknown-elf/7.2.0/../../../../riscv64-unknown-elf/bin/ld: bin/crt.o: can't link double-float modules with soft-float modules
/opt/riscv-rocket/lib/gcc/riscv64-unknown-elf/7.2.0/../../../../riscv64-unknown-elf/bin/ld: failed to merge target specific data of file bin/crt.o
collect2: error: ld returned 1 exit status
make: *** [Makefile:34: bin/out] Error 1
```