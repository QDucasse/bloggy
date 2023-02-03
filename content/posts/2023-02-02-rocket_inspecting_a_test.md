---
title: "Rocket test macros"
date: "2023-02-03"
tags: [
    "riscv",
    "rocket"
]
categories: [
    "Exploration"
]
---

## Unit test workflow recap

As presented in a previous post, the Rocket framework for unit tests revolves around the [riscv-tests](https://github.com/riscv-software-src/riscv-tests) repository. Those tests are separated by the extensions they use and the *Test Virtual Machine (TVM)* they should be run on. Simple macros expand the utilities and encodings are added to define instructions, *Control Status Registers (CSRs)*, etc.

Those tests are compiled using the RISC-V GNU toolchain, ([rocket-tools](https://github.com/chipsalliance/rocket-tools) in the case of Rocket) and installed in `/path/to/toolchain/riscv64-unknown-elf/share/riscv-tests/`. Both the binary and dump files are available in `benchmarks` and `isa`. 

This means that all RISC-V tests are directly available in a compiled format with their dump to look at, use and build on. However, this also means that adding a unit test in this framework to, let's say, add an instruction or a register, requires the developer to modify the complete toolchain. 

## Types and structures of tests

First of all, `riscv-tests` implements two types of tests, either simple unit tests per instruction (modulo the TVM and environment) that are implemented through direct assembly and macros or benchmarks that depends on more complex C files. The first are located in the `riscv-tests/isa` directory while the latter are in `riscv-tests/benchmarks`

The structure of the `isa` tests all use the [`test_macros.h`](https://github.com/riscv-software-src/riscv-tests/blob/master/isa/macros/scalar/test_macros.h) header that defines assembly stubs that can be used in the unit tests. Along with this file, each environment adds its `riscv_test.h` header and encodings defined in the [`riscv-test-env`](https://github.com/riscv/riscv-test-env) repository. Along with this environment are the linker scripts and eventual `vm` to simulate a virtual memory system.

Let's look at the `isa/rv64ui/simple.S` unit test:

```c
#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV64U
RVTEST_CODE_BEGIN

RVTEST_PASS

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END

```

As we can see, multiple macros are used to define the tests and the harness around them. To go quickly over them, they surround both the code and data section and provide some helpers. 

### Environment macros

For the environment macros defined in their respective environments, we will look at the `p` environment and the `rv64u` parameters so in `env/p/riscv_test.h` (most of the others depend on the `p` as the base one!):
- **`RVTEST_64U`**: is the base environment sets up the extension set we will be working with. It expands to:
```C
#define RVTEST_RV64U                      \
  .macro init;                            \
  .endm
```

> *Note* `.macro init` and `.endm` are [GNU Assembler macros](http://www.sourceware.org/binutils/docs-2.12/as.info/Macro.html) handled by [`binutils`](https://www.wikiwand.com/en/GNU_Binutils) that directly produce assembly!

The macro that expands into assembly code and is used if floating point numbers are required!

```C
#define RVTEST_RV64UF                     \
  .macro init;                            \
  RVTEST_FP_ENABLE;                       \
  .endm

#define RVTEST_FP_ENABLE                  \
  li a0, MSTATUS_FS & (MSTATUS_FS >> 1);  \
  csrs mstatus, a0;                       \
  csrwi fcsr, 0
```

- **`RVTEST_CODE_BEGIN`**: defines the starting point of the test and a way handle exceptions and trap vectors.

```C
#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  6;                                                      \
        .weak stvec_handler;                                            \
        .weak mtvec_handler;                                            \
        .globl _start;                                                  \
_start:                                                                 \
        /* reset vector */                                              \
        j reset_vector;                                                 \
        .align 2;                                                       \
trap_vector:                                                            \
        /* test whether the test came from pass/fail */                 \
        csrr t5, mcause;                                                \
        li t6, CAUSE_USER_ECALL;                                        \
        beq t5, t6, write_tohost;                                       \
        li t6, CAUSE_SUPERVISOR_ECALL;                                  \
        beq t5, t6, write_tohost;                                       \
        li t6, CAUSE_MACHINE_ECALL;                                     \
        beq t5, t6, write_tohost;                                       \
        /* if an mtvec_handler is defined, jump to it */                \
        la t5, mtvec_handler;                                           \
        beqz t5, 1f;                                                    \
        jr t5;                                                          \
        /* was it an interrupt or an exception? */                      \
  1:    csrr t5, mcause;                                                \
        bgez t5, handle_exception;                                      \
        INTERRUPT_HANDLER;                                              \
handle_exception:                                                       \
        /* we don't know how to handle whatever the exception was */    \
  other_exception:                                                      \
        /* some unhandlable exception occurred */                       \
  1:    ori TESTNUM, TESTNUM, 1337;                                     \
  write_tohost:                                                         \
        sw TESTNUM, tohost, t5;                                         \
        j write_tohost;                                                 \
reset_vector:                                                           \
        RISCV_MULTICORE_DISABLE;                                        \
        INIT_SATP;                                                      \
        INIT_PMP;                                                       \
        DELEGATE_NO_TRAPS;                                              \
        li TESTNUM, 0;                                                  \
        la t0, trap_vector;                                             \
        csrw mtvec, t0;                                                 \
        CHECK_XLEN;                                                     \
        /* if an stvec_handler is defined, delegate exceptions to it */ \
        la t0, stvec_handler;                                           \
        beqz t0, 1f;                                                    \
        csrw stvec, t0;                                                 \
        li t0, (1 << CAUSE_LOAD_PAGE_FAULT) |                           \
               (1 << CAUSE_STORE_PAGE_FAULT) |                          \
               (1 << CAUSE_FETCH_PAGE_FAULT) |                          \
               (1 << CAUSE_MISALIGNED_FETCH) |                          \
               (1 << CAUSE_USER_ECALL) |                                \
               (1 << CAUSE_BREAKPOINT);                                 \
        csrw medeleg, t0;                                               \
        csrr t1, medeleg;                                               \
        bne t0, t1, other_exception;                                    \
1:      csrwi mstatus, 0;                                               \
        init;                                                           \
        EXTRA_INIT;                                                     \
        EXTRA_INIT_TIMER;                                               \
        la t0, 1f;                                                      \
        csrw mepc, t0;                                                  \
        csrr a0, mhartid;                                               \
        mret;                                                           \
1:
```

> *Note:* The `1:` label is known as a **local symbol name** which, according to the [`gas` documentation](http://tigcc.ticalc.org/doc/gnuasm.html#SEC46), are: 
> - defined by writing a label of the form N: (where N represents any positive integer) and are 
> - referred to writing `Nb` or `Nf`, using the same number as when the label was defined with `Nb` being the most recent **previous** one and `Nf` the **following** definition (`b` standing for *backwards* and `f` for *forwards*)


- **`RVTEST_CODE_END`**: expands to `unimp` and should not be reached due to the `ecall` at the end of a test pass and fail (see below!)

- **`RVDATA_BEGIN`** and **`RVDATA_END`**: test the output data with a signature

```C
#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .pushsection .tohost,"aw",@progbits;                            \
        .align 6; .global tohost; tohost: .dword 0;                     \
        .align 6; .global fromhost; fromhost: .dword 0;                 \
        .popsection;                                                    \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:
```
> *Note:*  Look at what happens here 


- **`TESTNUM`**: defines the register that holds the current number of the test, in this case `gp`/`x3`


- **`RVTEST_PASS`** and **`RVTEST_FAIL`**: define the logic behind the 

```C
#define RVTEST_PASS                                                     \
        fence;                                                          \
        li TESTNUM, 1;                                                  \
        ecall

#define TESTNUM gp
#define RVTEST_FAIL                                                     \
        fence;                                                          \
1:      beqz TESTNUM, 1b;                                               \
        sll TESTNUM, TESTNUM, 1;                                        \
        or TESTNUM, TESTNUM, 1;                                         \
        ecall
```

### Test macros

The macros starting with `TEST_` are defined in `isa/macros/scalar/test_macros.h`:

- **`TEST_CASE`**: the base framework of all other tests, holding the test number, the register to test, the expected value that will be stored in `x7` and additional code can be specified.

```C
#define TEST_CASE( testnum, testreg, correctval, code... ) \
test_ ## testnum: \
    code; \
    li  x7, MASK_XLEN(correctval); \
    li  TESTNUM, testnum; \
    bne testreg, x7, fail;
```


- **`TEST_PASSFAIL`**: a wrapper around the previous test/fail logics. 
```C
#define TEST_PASSFAIL \
        bne x0, TESTNUM, pass; \
fail: \
        RVTEST_FAIL; \
pass: \
        RVTEST_PASS \
```

- Other macros are more instruction-specific such as:
    - `TEST_IMM_*` for immediate values 
    - `TEST_R_*` for one register
    - `TEST_RR_*` for two register
    - `TEST_LD_*` for loads
    - `TEST_ST_*` for stores


### Compiling a test

To compile an ISA test from the suite, the following `make` commands produces both the binary and the dump:

```bash
$ make rv64ui-p-addi.dump
```

> *Note:* The format is `[test family]-[TVM type]-[test name]`

The dump of the `simple` test presented earlier is the following, from which the different macros presented can be found expanded:

```dump
rv64ui-p-simple:     file format elf64-littleriscv


Disassembly of section .text.init:

0000000080000000 <_start>:
    80000000:	0480006f          	j	80000048 <reset_vector>

0000000080000004 <trap_vector>:
    80000004:	34202f73          	csrr	t5,mcause
    80000008:	00800f93          	li	t6,8
    8000000c:	03ff0863          	beq	t5,t6,8000003c <write_tohost>
    80000010:	00900f93          	li	t6,9
    80000014:	03ff0463          	beq	t5,t6,8000003c <write_tohost>
    80000018:	00b00f93          	li	t6,11
    8000001c:	03ff0063          	beq	t5,t6,8000003c <write_tohost>
    80000020:	00000f13          	li	t5,0
    80000024:	000f0463          	beqz	t5,8000002c <trap_vector+0x28>
    80000028:	000f0067          	jr	t5
    8000002c:	34202f73          	csrr	t5,mcause
    80000030:	000f5463          	bgez	t5,80000038 <handle_exception>
    80000034:	0040006f          	j	80000038 <handle_exception>

0000000080000038 <handle_exception>:
    80000038:	5391e193          	ori	gp,gp,1337

000000008000003c <write_tohost>:
    8000003c:	00001f17          	auipc	t5,0x1
    80000040:	fc3f2223          	sw	gp,-60(t5) # 80001000 <tohost>
    80000044:	ff9ff06f          	j	8000003c <write_tohost>

0000000080000048 <reset_vector>:
    80000048:	f1402573          	csrr	a0,mhartid
    8000004c:	00051063          	bnez	a0,8000004c <reset_vector+0x4>
    80000050:	00000297          	auipc	t0,0x0
    80000054:	01028293          	addi	t0,t0,16 # 80000060 <reset_vector+0x18>
    80000058:	30529073          	csrw	mtvec,t0
    8000005c:	18005073          	csrwi	satp,0
    80000060:	00000297          	auipc	t0,0x0
    80000064:	01c28293          	addi	t0,t0,28 # 8000007c <reset_vector+0x34>
    80000068:	30529073          	csrw	mtvec,t0
    8000006c:	fff00293          	li	t0,-1
    80000070:	3b029073          	csrw	pmpaddr0,t0
    80000074:	01f00293          	li	t0,31
    80000078:	3a029073          	csrw	pmpcfg0,t0
    8000007c:	00000297          	auipc	t0,0x0
    80000080:	01828293          	addi	t0,t0,24 # 80000094 <reset_vector+0x4c>
    80000084:	30529073          	csrw	mtvec,t0
    80000088:	30205073          	csrwi	medeleg,0
    8000008c:	30305073          	csrwi	mideleg,0
    80000090:	30405073          	csrwi	mie,0
    80000094:	00000193          	li	gp,0
    80000098:	00000297          	auipc	t0,0x0
    8000009c:	f6c28293          	addi	t0,t0,-148 # 80000004 <trap_vector>
    800000a0:	30529073          	csrw	mtvec,t0
    800000a4:	00100513          	li	a0,1
    800000a8:	01f51513          	slli	a0,a0,0x1f
    800000ac:	00055863          	bgez	a0,800000bc <reset_vector+0x74>
    800000b0:	0ff0000f          	fence
    800000b4:	00100193          	li	gp,1
    800000b8:	00000073          	ecall
    800000bc:	00000293          	li	t0,0
    800000c0:	00028e63          	beqz	t0,800000dc <reset_vector+0x94>
    800000c4:	10529073          	csrw	stvec,t0
    800000c8:	0000b2b7          	lui	t0,0xb
    800000cc:	1092829b          	addiw	t0,t0,265
    800000d0:	30229073          	csrw	medeleg,t0
    800000d4:	30202373          	csrr	t1,medeleg
    800000d8:	f66290e3          	bne	t0,t1,80000038 <handle_exception>
    800000dc:	30005073          	csrwi	mstatus,0
    800000e0:	00000297          	auipc	t0,0x0
    800000e4:	01428293          	addi	t0,t0,20 # 800000f4 <reset_vector+0xac>
    800000e8:	34129073          	csrw	mepc,t0
    800000ec:	f1402573          	csrr	a0,mhartid
    800000f0:	30200073          	mret
    800000f4:	0ff0000f          	fence
    800000f8:	00100193          	li	gp,1
    800000fc:	00000073          	ecall
    80000100:	c0001073          	unimp
    80000104:	0000                	unimp
    80000106:	0000                	unimp
    80000108:	0000                	unimp
    8000010a:	0000                	unimp
    8000010c:	0000                	unimp
    8000010e:	0000                	unimp
    80000110:	0000                	unimp
    80000112:	0000                	unimp
    80000114:	0000                	unimp
    80000116:	0000                	unimp
    80000118:	0000                	unimp
    8000011a:	0000                	unimp
    8000011c:	0000                	unimp
    8000011e:	0000                	unimp
    80000120:	0000                	unimp
    80000122:	0000                	unimp
    80000124:	0000                	unimp
    80000126:	0000                	unimp
    80000128:	0000                	unimp
    8000012a:	0000                	unimp
    8000012c:	0000                	unimp
    8000012e:	0000                	unimp
    80000130:	0000                	unimp
    80000132:	0000                	unimp
    80000134:	0000                	unimp
    80000136:	0000                	unimp
    80000138:	0000                	unimp
    8000013a:	0000                	unimp
```


In the next part, we will see how we can add a custom test and execute it through Rocket's emulator!