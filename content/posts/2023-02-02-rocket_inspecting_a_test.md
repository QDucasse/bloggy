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

Let's look at the `isa/rv64ui/addi.S` unit test:

```c
#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV64U
RVTEST_CODE_BEGIN

  TEST_IMM_OP( 2,  addi, 0x00000000, 0x00000000, 0x000 );
  [...]
  TEST_IMM_OP( 16, addi, 0x0000000080000000, 0x7fffffff, 0x001 );

  TEST_IMM_SRC1_EQ_DEST( 17, addi, 24, 13, 11 );

  TEST_IMM_DEST_BYPASS( 18, 0, addi, 24, 13, 11 );
  [...]
  TEST_IMM_SRC1_BYPASS( 23, 2, addi, 22, 13,  9 );

  TEST_IMM_ZEROSRC1( 24, addi, 32, 32 );
  TEST_IMM_ZERODEST( 25, addi, 33, 50 );

  TEST_PASSFAIL

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

- **`RVDATA_BEGIN`** and **`RVDATA_END`**: set up the characteristics of the data section:

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