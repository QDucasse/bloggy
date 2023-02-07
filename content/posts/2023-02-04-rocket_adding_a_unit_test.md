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


## Unit test workflow recap

As presented in a previous post, the Rocket framework for unit tests revolves around the [riscv-tests](https://github.com/riscv-software-src/riscv-tests) repository. Those tests are separated by the extensions they use and the *Test Virtual Machine (TVM)* they should be run on. Simple macros expand the utilities and encodings are added to define instructions, *Control Status Registers (CSRs)*, etc.

Those tests are compiled using the RISC-V GNU toolchain, ([rocket-tools](https://github.com/chipsalliance/rocket-tools) in the case of Rocket) and installed in `/path/to/toolchain/riscv64-unknown-elf/share/riscv-tests/`. Both the binary and dump files are available in `benchmarks` and `isa`. 

This means that all RISC-V tests are directly available in a compiled format with their dump to look at, use and build on. However, this also means that adding a unit test in this framework to, let's say, add an instruction or a register, requires the developer to modify the complete toolchain. 


## Unit test workaround

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

Using the same workaround as the FIXER authors, we will try to write and compile a test with a fictive instruction (we will look at how we can implement the instruction in the actual core later on). Starting with the `simple.S` file, we can build a simple test containing our instruction and the macro to pass!

1. Add a subdirectory `custom` in `isa`
2. Add our new `custom.S` test
3. Add the corresponding `Makefrag`
4. Extend the `isa/Makefile` with the compile framework for our directory

1- 

```bash
$ cd $ROCKET_ROOT/rocket-tools/riscv-tests/isa
$ mkdir custom
```

2-

```bash
$  cp rv64ui/simple.S custom/unknown.S
```

Modify the test as follows:

```c
#=======================================================================
#       Unknown instruction test
#-----------------------------------------------------------------------

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV64U
RVTEST_CODE_BEGIN

test_2:
  .word 0x0002a00b 
  
  RVTEST_PASS

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
```

3-
```bash
$ touch custom/Makefrag
```

Modify the makefrag as follows:

```make
#=======================================================================
# Makefrag for custom tests
#-----------------------------------------------------------------------

custom_sc_tests = \
	unknown \

custom_p_tests = $(addprefix custom-p-, $(custom_sc_tests))

spike_tests += $(custom_p_tests)
```

4-

In `isa/Makefile`, add the following line:

```make
...
$(eval $(call compile_template,rv64si,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64mi,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,custom,-march=rv64g -mabi=lp64))  <<<===
endif
...
```

## Compiling our new test


Once the new files/directories are created, we can now compile our test from the `isa` directory with :

```bash
$ make custom-p-unknown.dump
```

Reading the dump, we can look at our "fake" instruction:

```bash
$ cat custom-p-unknown.dump
custom-p-unknown:     file format elf64-littleriscv


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
    800000e4:	01428293          	addi	t0,t0,20 # 800000f4 <test_2>
    800000e8:	34129073          	csrw	mepc,t0
    800000ec:	f1402573          	csrr	a0,mhartid
    800000f0:	30200073          	mret

00000000800000f4 <test_2>:
    800000f4:	0002a00b          	0x2a00b       # <<<== Our custom instruction!
    800000f8:	0ff0000f          	fence
    800000fc:	00100193          	li	gp,1
    80000100:	00000073          	ecall
    80000104:	c0001073          	unimp
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

## Installing our new test

From the Rocket point of view, the test is fetched from the toolchain installation. Considering the toolchain is installed at `/opt/riscv-rocket/`, the binaries and dumps of each tests can be found in `/opt/riscv-rocket/riscv64-unknown-elf/share/riscv-tests/`.

Since we need our test to be installed here as well so Rocket can use a symbolic link to reference it in the emulator. Running the following commands in the `riscv-tests` directory should be enough:
```bash
$ ./configure --prefix=$RISCV/riscv64-unknown-elf
$ make install
```

The test and its should now show up in `$RISCV/riscv64-unknown-elf/share/riscv-tests/isa`!


## Running the test on the emulator

Going to the `rocket-chip` directory in the emulator, running `make output/custom-p-unknown.out` does not work at all, it builds the emulator and verilator then fails not finding a `makefile` rule...


The issue comes form two distinct files where the `makefiles` are generated and the default test suite is defined. The first one is [`AddDefaultTests.scala`](https://github.com/chipsalliance/rocket-chip/blob/master/src/main/scala/stage/phases/AddDefaultTests.scala) from which we learn that the test environment is setup according to the test name and our custom test will not be found. Next, in [`RocketTestSuite.scala`](https://github.com/chipsalliance/rocket-chip/blob/master/src/main/scala/system/RocketTestSuite.scala), the tests suite and their corresponding `makefiles` are described. As an example, the `AssemblyTestSuite` extends the base `RocketTestSuite` with all information in its `toString` method:

```scala
abstract class RocketTestSuite {
  val dir: String
  val makeTargetName: String
  val names: LinkedHashSet[String]
  val envName: String
  def kind: String
  def postScript = s"""

$$(addprefix $$(output_dir)/, $$(addsuffix .hex, $$($makeTargetName))): $$(output_dir)/%.hex: $dir/%.hex
\tmkdir -p $$(output_dir)
\tln -fs $$< $$@

$$(addprefix $$(output_dir)/, $$($makeTargetName)): $$(output_dir)/%: $dir/%
\tmkdir -p $$(output_dir)
\tln -fs $$< $$@

run-$makeTargetName: $$(addprefix $$(output_dir)/, $$(addsuffix .out, $$($makeTargetName)))
\t@echo; perl -ne 'print "  [$$$$1] $$$$ARGV \\t$$$$2\\n" if( /\\*{3}(.{8})\\*{3}(.*)/ || /ASSERTION (FAILED):(.*)/i )' $$^ /dev/null | perl -pe 'BEGIN { $$$$failed = 0 } $$$$failed = 1 if(/FAILED/i); END { exit($$$$failed) }'

run-$makeTargetName-debug: $$(addprefix $$(output_dir)/, $$(addsuffix .vpd, $$($makeTargetName)))
\t@echo; perl -ne 'print "  [$$$$1] $$$$ARGV \\t$$$$2\\n" if( /\\*{3}(.{8})\\*{3}(.*)/ || /ASSERTION (FAILED):(.*)/i )' $$(patsubst %.vpd,%.out,$$^) /dev/null | perl -pe 'BEGIN { $$$$failed = 0 } $$$$failed = 1 if(/FAILED/i); END { exit($$$$failed) }'

run-$makeTargetName-fst: $$(addprefix $$(output_dir)/, $$(addsuffix .fst, $$($makeTargetName)))
\t@echo; perl -ne 'print "  [$$$$1] $$$$ARGV \\t$$$$2\\n" if( /\\*{3}(.{8})\\*{3}(.*)/ || /ASSERTION (FAILED):(.*)/i )' $$(patsubst %.fst,%.out,$$^) /dev/null | perl -pe 'BEGIN { $$$$failed = 0 } $$$$failed = 1 if(/FAILED/i); END { exit($$$$failed) }'
"""
}

class AssemblyTestSuite(prefix: String, val names: LinkedHashSet[String])(val envName: String) extends RocketTestSuite {
  val dir = "$(RISCV)/riscv64-unknown-elf/share/riscv-tests/isa"
  val makeTargetName = prefix + "-" + envName + "-asm-tests"
  def kind = "asm"
  override def toString = s"$makeTargetName = \\\n" + names.map(n => s"\t$prefix-$envName-$n").mkString(" \\\n") + postScript
}
```

At the end of the file, the name of the `DefaultTestSuites` are added by hand in their respective lists:

```scala
  val rv32uiNames = LinkedHashSet(
    "simple", "add", "addi", "and", "andi", "auipc", "beq", "bge", "bgeu", "blt", "bltu", "bne", "fence_i",
    "jal", "jalr", "lb", "lbu", "lh", "lhu", "lui", "lw", "or", "ori", "sb", "sh", "sw", "sll", "slli",
    "slt", "slti", "sra", "srai", "srl", "srli", "sub", "xor", "xori")
  val rv32ui = new AssemblyTestSuite("rv32ui", rv32uiNames)(_)

  val rv32ucNames = LinkedHashSet("rvc")
  val rv32uc = new AssemblyTestSuite("rv32uc", rv32ucNames)(_)

  val rv32umNames = LinkedHashSet("mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu")
  val rv32um = new AssemblyTestSuite("rv32um", rv32umNames)(_)
  ...
  val rv64uc = new AssemblyTestSuite("rv64uc", rv64ucNames)(_)
  ...
  val rv64u = List(rv64ui, rv64um)
  val rv64i = List(rv64ui, rv64si, rv64mi)
  val rv64pi = List(rv64ui, rv64mi)
```

To make everything work this way, we need to move our custom test in the `rv64ui` folder, add it to the `Makefrag` and reinstall it... We also need to add the following lines to `RocketTestSuite.scala`, defining our test and adding it to the assembly suite:
```scala
...
val rv64uiCustomNames = LinkedHashSet("custom")
val rv64ui = new AssemblyTestSuite("rv64ui", rv32uiNames ++ rv64uiNames ++ rv64uiCustomNames)(_)
...
```

Launching the emulator "runs" our new test! (fails on our undefined instruction but hey that's the point)

```bash
$ make output/r64ui-p-custom.out
... ~ building rocket
... ~ building verilator
```

Looking at the dump:
```bash
...
C0:      10735 [1] pc=[00000000800000e0] W[r 5=00000000800000e0][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[00000297] auipc   t0, 0x0
C0:      10736 [1] pc=[00000000800000e4] W[r 5=00000000800000f4][1] R[r 5=00000000800000e0] R[r 0=0000000000000000] inst=[01428293] addi    t0, t0, 20
C0:      10737 [1] pc=[00000000800000e8] W[r 0=0000003f043f3390][1] R[r 5=00000000800000f4] R[r 0=0000000000000000] inst=[34129073] csrw    mepc, t0
C0:      10738 [1] pc=[00000000800000ec] W[r10=0000000000000000][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[f1402573] csrr    a0, mhartid
C0:      10739 [1] pc=[00000000800000f0] W[r 0=0000000000000000][0] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[30200073] mret
C0:      10744 [0] pc=[00000000800000f4] W[r 0=0000000000000000][0] R[r 5=000000000002a00b] R[r 0=0000000000000000] inst=[0002a00b] custom0.rs1 (args unknown)
C0:      10803 [1] pc=[0000000080000004] W[r30=0000000000000002][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[34202f73] csrr    t5, mcause
C0:      10804 [1] pc=[0000000080000008] W[r31=0000000000000008][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[00800f93] li      t6, 8
C0:      10806 [1] pc=[000000008000000c] W[r 0=0000000000000000][0] R[r30=0000000000000002] R[r31=0000000000000008] inst=[03ff0863] beq     t5, t6, pc + 48
...
C0:      32464 [1] pc=[0000000000000840] W[r 0=0000000000000000][0] R[r 0=0000000000000000] R[r 8=0000000000000000] inst=[10802423] sw      s0, 264(zero)
C0:      32465 [1] pc=[0000000000000844] W[r 8=2c2eb378ce6af372][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[7b202473] csrr    s0, dscratch
C0:      32466 [1] pc=[0000000000000848] W[r 0=0000000000000000][0] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[7b200073] dret
C0:      32493 [1] pc=[0000000080000040] W[r 0=0000000000000000][0] R[r30=000000008000103c] R[r 3=0000000000000539] inst=[fc3f2223] sw      gp, -60(t5)
C0:      32494 [1] pc=[0000000080000044] W[r 0=0000000080000048][1] R[r 0=0000000000000000] R[r 0=0000000000000000] inst=[ff9ff06f] j       pc - 0x8
*** FAILED *** (tohost = 668)
*** FAILED *** via dtm (code = 668, seed 1675659022) after 32804 cycles

```

Our instruction got executed!!

> Note: Is this the correct way to do it? We probably would like to keep a separate structure for our custom tests, or simply generate them then pass them directly to the emulator? Eh, I thought unit tests meant simple reproducible tests that we can use to learn the workflow of Rocket but they are mainly validation tests