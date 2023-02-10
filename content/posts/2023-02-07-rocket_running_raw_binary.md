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
- `-S` or `--metmaxsize` the maximum size of a method

For now, let's generate a small binary with 2 methods of max size 5 instructions, no PICs, and a small gap between the interpretation loop and the JIT code by using:
```bash
$ python -m gigue -N 2 -S 5 -R 0 -I 0 -J 224
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
    out.bin out.o
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
$ ./emulator-freechips.rocketchip.system-freechips.rocketchip.system.DefaultConfig \
    +max-cycles=100000000 \
    +verbose \
    gigue/bin/out.o
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
    ├── template.S
    └── util.h

1 directory, 5 files
```

Note that to add our raw binary in an ELF file, rather than using `objcopy`, we can use the assembly `.incbin` operator! We use a template assembly file that includes the raw binary and redefines the `main` function to call it then exit. Our `main` function will override the one defined in `syscalls` as it was defined with the `weak` adjective. This way, we use the following `template.S` file:
```nasm
.global gigue_start
gigue_start:
    .incbin "bin/out.bin"

.global gigue_end
gigue_end:

.global gigue_size
gigue_size:
    .int gigue_end - gigue_start


; .text.startup:
    .global main
main:
    call gigue_start
    j exit
```

Running `make` in the Gigue root repository should compile each file and link them together! 
```bash
$ export RISCV=/path/to/toolchain
$ make
/opt/riscv-rocket/bin/riscv64-unknown-elf-gcc -Iresources/common -march=rv64gc -mabi=lp64d -DPREALLOCATE=1 -mcmodel=medany -static -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf resources/common/syscalls.c -c -o bin/syscalls.o 
/opt/riscv-rocket/bin/riscv64-unknown-elf-gcc -Iresources/common -march=rv64gc -mabi=lp64d -DPREALLOCATE=1 -mcmodel=medany -static -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf resources/common/crt.S -c -o bin/crt.o 
/opt/riscv-rocket/bin/riscv64-unknown-elf-gcc -Iresources/common -march=rv64gc -mabi=lp64d -DPREALLOCATE=1 -mcmodel=medany -static -std=gnu99 -O2 -ffast-math -fno-common -fno-builtin-printf resources/common/template.S -c -o bin/template.o 
/opt/riscv-rocket/bin/riscv64-unknown-elf-gcc -static -nostdlib -nostartfiles -lm -lgcc -T resources/common/test.ld bin/syscalls.o bin/crt.o bin/template.o -o bin/out
```

We can also generate the dumps of the different binaries, `out.bin.dump` to look at the Gigue-generated binary (passed through `objcopy`) or `out.dump` to look at the complete executable dump:
```bash
$ make dump
/opt/riscv-rocket/bin/riscv64-unknown-elf-objdump --disassemble-all --disassemble-zeroes --section=.text --section=.text.startup --section=.text.init --section=.data bin/out > bin/out.dump
/opt/riscv-rocket/bin/riscv64-unknown-elf-objcopy -I binary -O elf64-littleriscv -B riscv --rename-section .data=.text bin/out.bin bin/out.bin.dump.temp
/opt/riscv-rocket/bin/riscv64-unknown-elf-objdump --disassemble-all --disassemble-zeroes --section=.text --section=.text.startup --section=.text.init --section=.data bin/out.bin.dump.temp > bin/out.bin.dump
rm bin/out.bin.dump.temp
```


## Running it back on Rocket

Now retrying on Rocket, running the instructions through the spike disssembly this time and outputting the result in the `out.dis` file:
```bash
$ ./emulator-freechips.rocketchip.system-freechips.rocketchip.system.DefaultConfig \
    +max-cycles=100000000 \
    +verbose \
    gigue/bin/out \
    3>&1 1>&2 2>&3 | spike-dasm > gigue/bin/out.dis
```


Inpecting the disassembly output, our code has been executed!!!
```
C0:     133134 [1] pc=[0000000080002734] W[r 2=0000000080022a28][1] R[r 2=0000000080022a80] R[r 0=0000000000000000] inst=[fa810113] addi    sp, sp, -88
C0:     133163 [1] pc=[0000000080002738] W[r 0=0000000000000000][0] R[r 2=0000000080022a28] R[r 8=0000000000000000] inst=[00813023] sd      s0, 0(sp)
C0:     133164 [1] pc=[000000008000273c] W[r 0=0000000000000000][0] R[r 2=0000000080022a28] R[r 9=0000000000000000] inst=[00913423] sd      s1, 8(sp)
C0:     133180 [1] pc=[0000000080002740] W[r 0=0000000000000000][0] R[r 2=0000000080022a28] R[r18=0000000080002b28] inst=[01213823] sd      s2, 16(sp)
C0:     133197 [1] pc=[0000000080002744] W[r 0=0000000000000000][0] R[r 2=0000000080022a28] R[r19=0000000000000000] inst=[01313c23] sd      s3, 24(sp)
C0:     133198 [1] pc=[0000000080002748] W[r 0=0000000000000000][0] R[r 2=0000000080022a28] R[r20=0000000000000001] inst=[03413023] sd      s4, 32(sp)
C0:     133199 [1] pc=[000000008000274c] W[r 0=0000000000000000][0] R[r 2=0000000080022a28] R[r21=0000000080002b40] inst=[03513423] sd      s5, 40(sp)
C0:     133200 [1] pc=[0000000080002750] W[r 0=0000000000000000][0] R[r 2=0000000080022a28] R[r22=0000000000000000] inst=[03613823] sd      s6, 48(sp)
C0:     133201 [1] pc=[0000000080002754] W[r 0=0000000000000000][0] R[r 2=0000000080022a28] R[r23=0000000000000000] inst=[03713c23] sd      s7, 56(sp)
C0:     133202 [1] pc=[0000000080002758] W[r 0=0000000000000000][0] R[r 2=0000000080022a28] R[r24=0000000000000000] inst=[05813023] sd      s8, 64(sp)
C0:     133203 [1] pc=[000000008000275c] W[r 0=0000000000000000][0] R[r 2=0000000080022a28] R[r25=0000000000000000] inst=[05913423] sd      s9, 72(sp)
C0:     133204 [1] pc=[0000000080002760] W[r 0=0000000000000000][0] R[r 2=0000000080022a28] R[r 1=0000000080002948] inst=[04113823] sd      ra, 80(sp)
C0:     133205 [1] pc=[0000000080002764] W[r 1=0000000080002764][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[00000097] auipc   ra, 0x0
C0:     133206 [1] pc=[0000000080002768] W[r 1=000000008000276c][1] R[r 1=0000000080002764] R[r 0=0000000000000000] inst=[0b0080e7] jalr    ra, ra, 176
C0:     133244 [1] pc=[0000000080002814] W[r 2=0000000080022a10][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[fe810113] addi    sp, sp, -24
C0:     133245 [1] pc=[0000000080002818] W[r 0=0000000000000000][0] R[r 2=0000000080022a10] R[r 8=0000000000000000] inst=[00813023] sd      s0, 0(sp)
C0:     133246 [1] pc=[000000008000281c] W[r 7=0000000000000000][0] R[r29=0000000000000000] R[r31=0000000000000000] inst=[03feb3b3] mulhu   t2, t4, t6
C0:     133256 [1] pc=[0000000080002820] W[r 7=fffffffffffffd0c][1] R[r17=0000000000000000] R[r 0=0000000000000000] inst=[d0c8839b] addiw   t2, a7, -756
C0:     133257 [1] pc=[0000000080002824] W[r10=0000000000000000][1] R[r 6=0000000000000000] R[r 0=0000000000000000] inst=[e8232513] slti    a0, t1, -382
C0:     133258 [1] pc=[0000000080002828] W[r10=0000000000000000][1] R[r11=0000000000000000] R[r31=0000000000000000] inst=[01f5f533] and     a0, a1, t6
C0:     133259 [1] pc=[000000008000282c] W[r 8=0000000000000000][1] R[r 2=0000000080022a10] R[r 0=0000000000000000] inst=[00013403] ld      s0, 0(sp)
C0:     133260 [1] pc=[0000000080002830] W[r 2=0000000080022a28][1] R[r 2=0000000080022a10] R[r 0=0000000000000000] inst=[01810113] addi    sp, sp, 24
C0:     133261 [1] pc=[0000000080002834] W[r 0=0000000080002838][1] R[r 1=000000008000276c] R[r 0=0000000000000000] inst=[00008067] ret
C0:     133262 [1] pc=[000000008000276c] W[r 5=0000000000000001][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[00100293] li      t0, 1
C0:     133263 [1] pc=[0000000080002770] W[r 1=0000000080002770][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[00000097] auipc   ra, 0x0
C0:     133264 [1] pc=[0000000080002774] W[r 1=0000000080002778][1] R[r 1=0000000080002770] R[r 0=0000000000000000] inst=[0c8080e7] jalr    ra, ra, 200
C0:     133268 [1] pc=[0000000080002838] W[r 6=0000000000000001][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[00100313] li      t1, 1
C0:     133269 [1] pc=[000000008000283c] W[r 0=0000000000000000][0] R[r 6=0000000000000001] R[r 5=0000000000000001] inst=[00531463] bne     t1, t0, pc + 8
C0:     133335 [1] pc=[0000000080002840] W[r 0=0000000080002844][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[01c0006f] j       pc + 0x1c
C0:     133337 [1] pc=[000000008000285c] W[r 0=0000000080002860][1] R[r 1=0000000080002778] R[r 0=0000000000000000] inst=[00008067] ret
C0:     133339 [1] pc=[0000000080002778] W[r 8=0000000000000000][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[00013403] ld      s0, 0(sp)
C0:     133340 [1] pc=[000000008000277c] W[r 9=0000000000000000][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[00813483] ld      s1, 8(sp)
C0:     133341 [1] pc=[0000000080002780] W[r18=0000000080002b28][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[01013903] ld      s2, 16(sp)
C0:     133342 [1] pc=[0000000080002784] W[r19=0000000000000000][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[01813983] ld      s3, 24(sp)
C0:     133343 [1] pc=[0000000080002788] W[r20=0000000000000001][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[02013a03] ld      s4, 32(sp)
C0:     133344 [1] pc=[000000008000278c] W[r21=0000000080002b40][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[02813a83] ld      s5, 40(sp)
C0:     133345 [1] pc=[0000000080002790] W[r22=0000000000000000][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[03013b03] ld      s6, 48(sp)
C0:     133346 [1] pc=[0000000080002794] W[r23=0000000000000000][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[03813b83] ld      s7, 56(sp)
C0:     133347 [1] pc=[0000000080002798] W[r24=0000000000000000][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[04013c03] ld      s8, 64(sp)
C0:     133348 [1] pc=[000000008000279c] W[r25=0000000000000000][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[04813c83] ld      s9, 72(sp)
C0:     133349 [1] pc=[00000000800027a0] W[r 1=0000000080002948][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[05013083] ld      ra, 80(sp)
C0:     133350 [1] pc=[00000000800027a4] W[r 2=0000000080022a80][1] R[r 2=0000000080022a28] R[r 0=0000000000000000] inst=[05810113] addi    sp, sp, 88
C0:     133351 [1] pc=[00000000800027a8] W[r 0=00000000800027ac][1] R[r 1=0000000080002948] R[r 0=0000000000000000] inst=[00008067] ret
```

We can distinguish the interpretation loop prologue and epilogue (with `sd`/`ld`s), then the two JIT methods (ending with `ret`s)!