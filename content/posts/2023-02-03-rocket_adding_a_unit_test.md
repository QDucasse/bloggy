---
title: "Adding a unit test in Rocket"
date: "2023-02-03"
tags: [
    "riscv",
    "rocket"
]
categories: [
    "Exploration"
]
---

## Unit test workaround

All RISC-V tests are directly available in a compiled format with their dump to look at, use and build on. However, adding a unit test in the Rocket framework to, let's say, add an instruction or a register, requires the developer to modify the complete toolchain.

To circumvent the need to change the entire toolchain to test additions to the binary, authors of [FIXER](https://ieeexplore.ieee.org/document/8714980) used the toolchain to generate a binary that they then tagged and expanded with the direct binary corresponding of their custom instruction. For example, they add *Control Flow Integrity (CFI)* mechanisms to check forward-edge and backward-edge control flow through tags:

```C
void main () {          void myFunc() {
    ...                     ...
    CFI_CALL                CFI_RET
    myFunc();               return;
    ...                 }
}
```

That then get directly expanded to the binary representation of the instruction. They use the `custom` instructions already available in the Rocket decoder and usable through their [*Simple Custom Instruction Extension (SCIE)*](https://github.com/chipsalliance/rocket-chip/blob/master/src/main/scala/scie/SCIE.scala). The expanded assembly looks like the following:

```asm
# CFI_CALL               # CFI_RET    
auipc t0,0               .word 0x0200428b
add t0,t0,14             bne t0,ra,_cfi_error
.word 0x0002a00b         jr ra
call myFun
```

## Writing our own unit test

Using the same workaround as the FIXER authors, we will try to write and compile a test with a fictive instruction (we will look at how we can implement the instruction in the actual core later on).