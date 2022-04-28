---
title: "RISC-V load immediate pseudo-instruction"
date: "2022-02-21"
tags: [
    "riscv",
]
categories: [
    "Guide"
]
---


# RISC-V Load Immediate `li` Pseudo-Instruction

The pseudo-instruction `li` breaks down to a complex algorithm depending on the variables. Before presenting the algorithm, some terms have to be defined.

## Terms and Concepts

### Numbers and Sign

First, an **unsigned number** has its raw value in binary and cannot be negative. There is no guess on how to read the value, each bit will only represent a power of two.

```
 1   0   1   1
2^3 2^2 2^1 2^0
 8 + 0 + 2 + 1  = 11
```

Next, a **signed integer** will have its most significant bit set to a sign bit. A naive representation would be to note if the sign bit is one, in which case the number is negative, then interpret the rest of the number. However, this makes the value 0 and -0 have a different representation.

```
 1   0   1   1
 -  2^2 2^1 2^0
 - ( 0 + 2 + 1 ) = -3
```

Another issue with this representation is the fact that you have to take extra care of operations. For example:

```
   1011 (-3)
 + 1010 (-2)
 ______
   0101 (+5)  X incorrect
```

The real answer is `10101` but if we are limited to 4 bits, the extra digit is simply lost...

The solution to this representation is **two's complement**, inverting all bits of the positive integer and add 1 to get its negative representation.

```
7 --> 0111 --> 1000 --> 1001 --> -7
       (7)   (2s ct)    (+1)     
```

If we now try another operation:

```
	1001 (-7)
  + 0100 (+4)
  ______
    1101  sign bit up so the value is negative!
   	      remove bit sign and subtract 1 -> 100 = 4
      => -4  CORRECT!
```



### In Pharo

While these are basic number representation concepts, in Pharo, writing `-16rF22` is possible and the inspector will tell you it is equal to -3874. However, if what you mean is *perform the two's complement of that number*, you can use a function such as:

```smalltalk
computeSignedValueOf: aValue ofSize: aSize
	"If the number is negative, returns two's complement, otherwise return the value"
	aValue < 0
		ifTrue: [ ^ aValue twoComplementOfBitSize: aSize ]  "Compute two's complement"
		ifFalse: [ ^ aValue ]
```



### Sign Extension

Another concept that is important regarding signed and unsigned numbers is the concept of **sign extension** and **zero extension**. When moving a number around or extracting a number from a bit array, it is important to **extend** it to the destination size. How should you extend it then? Add 0s as the higher bits?

Two methods coexist: the first one is called **sign-extension** and will write the sign bit of the number as all the higher bits while **zero-extension** will write 0s. The first one has to be used when dealing with **signed numbers** while the latter is preferred for **unsigned numbers**.

For example, moving the signed value -222 (`16r22` with the smallest size of 8 bits) should be **sign-extended** to `16rFFFFFF22` when moved in a 32-bits register. This will not change the value due to how two's complement work! On the other hand, when moving an unsigned number it is important to keep the bits raw as they directly represent the number.

In C or C++, sign-extension is usually performed as follows:

```c
uint64_t x;
// Extract the lower n bits of x and sign-extend them
int64_t low12 = (int64_t)((x << (64 - n)) >> (64 -n))
```

Using the fact that causing an overflow in a left shift will truncate the number, shifting left then shifting right the same amount will truncate the value at the given shift amount. The cast to `int64_t` from `uint64_t` will perform the sign extension!



## Load Immediate `li` pseudo-instruction

Loading an immediate in RISC-V means loading a raw value in a register. While this can be done with a single load operation on architectures such as x86, the path is more convoluted for RISC-V.

### Instructions Available

We have four different instructions that we can combine to load a particular immediate. Those are:

- **Load Upper Immediate `lui`:** Writes the **sign-extended** 20-bit immediate, left-shifted by 12 bits to x[*rd*], zeroing the lower 12 bits. This translates to:

  ```ruby
  x[rd] = sext(immediate[31:12] << 12)
  ```

- **Add Immediate `addi`:** Adds the **sign-extended** 12-bits immediate to register x[*rs1*] and writes the result to x[*rd*]. This translates to:

  ```ruby
  x[rd] = x[rs1] + sext(immediate)
  ```

- **Add Word Immediate `addiw`:** Adds the **sign-extended** 12-bits immediate to register x[*rs1*], truncates the result to 32 bits, and writes the **sign-extended** result to x[*rd*]. This translates to:

  ```ruby
  x[rd] = sext((x[rs1] + sext(immediate))[31:0])  
  ```

- **Shift Left Logical Immediate `slli`:** Shifts register x[*rs1*] left by *shamt* positions. The vacated bits are filled with zeros, and the result is written to x[*rd*]. This translates to:

  ```ruby
  x[rd] = x[rs1] << shamt
  ```



Using these four instructions, we can easily (naively) figure how we could load an immediate. Depending on the size of the immediate, we can use from 1 to 8 instructions: `addi` if it fits less than 12 bits or up to `lui`, `addiw`, `slli`, `addi`, `slli`, `addi`, `slli`, `addi`. Note that the first two instructions `lui` + `addiw` can contribute up to 32 bits while the following `addi` contribute up to 12 bits each. We first emit the 32 most significant bits with `lui`+`addiw` then work our way with shifts and adds.

However, this idea does not work due to the fact that EACH `addi` and `addiw` performs a **sign-extension**. This means that if a big constant (let's say `0x7000000000000800` or 8070450532247930880) has to be loaded, the final part where you perform the add will get understood as a signed integer due to the most significant bit set to 1.

### ASM Exploration

Using `clang` and `llvm-objdump`, let's look at how the compiler handles the translation!

Using `clang` makes it possible to generate an object file from the asm with:

```bash
$ clang -c -target riscv64 -march=rv64g -g load_immediate.s -o load_immediate.o
```

`load_immediate.s` is composed of:

```
    .org 0x1000
 main:
    li x7, 12341234
```

The generated object file can be read with `objdump`:

```bash
$ llvm-objdump -S load_immediate.o
```

A simple Python script automates the process in the command line:

```python
import sys
import subprocess

if len(sys.argv) != 2:
    print("Wrong arguments! Use as python immediate.py <your 64-bits immediate value>")
    sys.exit(1)

with open("temp.s", "w") as file:
    file.write("""    .org 0x1000
 main:
    li x7, {}""".format(sys.argv[1]))

subprocess.run(['clang', '-c', '-target', 'riscv64', '-march=rv64g',
                         '-g', 'temp.s', '-o', 'temp.o'])

result = subprocess.run(['llvm-objdump', '-S', 'temp.o'], stdout=subprocess.PIPE)
print(result.stdout.decode('utf-8'))
```



### ASM Examples

Let's look at some examples of the result of `objdump`:

- **7FF:**

  ```bash
  0000000000001000 main:
  ;     li x7, 0x7FF
  1000: 93 03 f0 7f          	addi	t2, zero, 2047  # 0x7FF
  ```

- **FF0:**

  ```bash
  0000000000001000 main:
  ;     li x7, 0xFF0
  1000: b7 13 00 00          	lui	t2, 1           # 0x1
  1004: 9b 83 03 ff          	addiw	t2, t2, -16 # 0xFF0
  ```

The first example loads the value within 11 bits (sign bit 0) so a simple `addi` is enough. On the other hand, the second value, `FF0` will be understood as the two's complement of 16 and the emitted instruction will be `addi rd, rs, -16`. Leaving this instruction alone will sign-extend the value -16 to the size of the register. Instead of having only the value `FF0` in the register, we would have `FFFFFFF0` (for 32 bits).  One way to solve the problem is to add 1 through `lui` so that the sign bit will be reset:

```
    0000 1000
  + FFFF FFF0
  ___________
    0000 0FF0
```

>  **A simple check on the sign bit of the 12 bits immediate should work!**

*But what happens when the value `lui` should manage gets negated too?*

---

Let's look into some more ASM examples:

- **7FF00FF0:**

  ```bash
  0000000000001000 main:
  ;     li x7, 0x7FF00FF0
  1000: b7 13 f0 7f          	lui	t2, 524033       # 0x7FF01
  1004: 9b 83 03 ff          	addiw	t2, t2, -16  # 0xFF0

  ```

- **FFF00FF0:**

  ```bash
  0000000000001000 main:
  ;     li x7, 0xFFF00FF0
  1000: b7 03 10 00          	lui	t2, 256           # 0x100
  1004: 9b 83 13 f0          	addiw	t2, t2, -255  # 0xF01
  1008: 93 93 c3 00          	slli	t2, t2, 12
  100c: 93 83 03 ff          	addi	t2, t2, -16   # 0xFF
  ```

While the first example is straightforward, the second one is more convoluted, we will look into this one. To handle the sign extension `lui` performs, a new instruction is added! The first two will do an addition between `0x00100000` (`lui` loads 256 then shifts it left by 12 bits) and `0xFFFFFF01` (`addiw` uses the ***sign-extended*** value -255). The result is:

```
   0010 0000
 + FFFF FF01
 ___________
   000F FF01
```

which corresponds to our value `0xFFF00` with the added 1 since the next value has the sign bit set and has to be corrected as presented in the examples earlier.

> **An additional instruction can handle the shift the issue and handle the problem of sign-extension for `lui`!**



## LLVM Solution

*How does LLVM handles this rather complicated algorithm (and even better than that, it can also adapt the shifts in case of scarce values)?*

(https://github.com/llvm/llvm-project/blob/4c3d916c4bd2a392101c74dd270bd1e6a4fec15b/llvm/lib/Target/RISCV/MCTargetDesc/RISCVMatInt.cpp)

```c++
static void generateInstSeqImpl(int64_t Val,
                                 const FeatureBitset &ActiveFeatures,
                                 RISCVMatInt::InstSeq &Res) {
   // Check for 64 bits
   bool IsRV64 = ActiveFeatures[RISCV::Feature64Bit];  
   assert(IsRV64 && "Can't emit >32-bit imm for non-RV64 target");

   // Check if the value fits in 32-bits
   if (isInt<32>(Val)) {
     // Depending on the active bits in the immediate Value v, the following
     // instruction sequences are emitted:
     //
     // v == 0                        : ADDI
     // v[0,12) != 0 && v[12,32) == 0 : ADDI
     // v[0,12) == 0 && v[12,32) != 0 : LUI
     // v[0,32) != 0                  : LUI+ADDI(W)
     int64_t Hi20 = ((Val + 0x800) >> 12) & 0xFFFFF;
     int64_t Lo12 = SignExtend64<12>(Val);

     if (Hi20)
       Res.push_back(RISCVMatInt::Inst(RISCV::LUI, Hi20));

     if (Lo12 || Hi20 == 0) {
       unsigned AddiOpc = (IsRV64 && Hi20) ? RISCV::ADDIW : RISCV::ADDI;
       Res.push_back(RISCVMatInt::Inst(AddiOpc, Lo12));
     }
     return;
   }

   // In the following, constants are processed from LSB to MSB but instruction
   // emission is performed from MSB to LSB by recursively calling
   // generateInstSeq. In each recursion, first the lowest 12 bits are removed
   // from the constant and the optimal shift amount, which can be greater than
   // 12 bits if the constant is sparse, is determined. Then, the shifted
   // remaining constant is processed recursively and gets emitted as soon as it
   // fits into 32 bits. The emission of the shifts and additions is subsequently
   // performed when the recursion returns.
   int64_t Lo12 = SignExtend64<12>(Val); // (int64_t)((Val << (64 -12)) >> (64 -12))
   int64_t Hi52 = ((uint64_t)Val + 0x800ull) >> 12;
   int ShiftAmount = 12 + findFirstSet((uint64_t)Hi52);
   Hi52 = SignExtend64(Hi52 >> (ShiftAmount - 12), 64 - ShiftAmount);
   // If the remaining bits don't fit in 12 bits, we might be able to reduce the
   // shift amount in order to use LUI which will zero the lower 12 bits.
   if (ShiftAmount > 12 && !isInt<12>(Hi52) && isInt<32>((uint64_t)Hi52 << 12)) {
     // Reduce the shift amount and add zeros to the LSBs so it will match LUI.
     ShiftAmount -= 12;
     Hi52 = (uint64_t)Hi52 << 12;
   }
   // Recursive call
   generateInstSeqImpl(Hi52, ActiveFeatures, Res);
   // Generation of the instruction
   Res.push_back(RISCVMatInt::Inst(RISCV::SLLI, ShiftAmount));
   if (Lo12)
     Res.push_back(RISCVMatInt::Inst(RISCV::ADDI, Lo12));
 }
```

Let's understand this piece of recursive code step by step. Note that the given value is a 64-bits signed integer!

0. If the value fits in 32 bits, it **splits it in 20 + 12** and performs the usual `lui`+`addi(w)` *\*if needed\**

   *Note: Since this code is used recursively, this is the last part that will execute.*

   Otherwise:

1. **Extract** the **lowest 12 bits** from the constant and sign-extended to 64 bits.

2. **Extract** the **highest 52 bits** by first adding `0x800` then shifting left by 12 bits.

    *Note: the addition will automatically verify the bit sign, if it is 1 it will be propagated as we want otherwise it will not do anything.*

3. **Find** the optimal **shift amount** by looking into the highest 52 bits for the **first set bit**, if it is greater than 12, shift the `Hi52` as well so it takes it in consideration.

4. If the remaining bits do not fit in 12 bits, the shift amount can be reduced following certain conditions.

5. Finally, call **recursively** the function and push back the FF0

*Note: The constant is processed from LSB to MSB (right to left) but instruction emission is performed from MSB to LSB (right to left).*

##  Notes:

- LLVM Comments:

*In the worst case, for a full 64-bit constant, a sequence of 8 instructions (i.e., LUI+ADDIW+SLLI+ADDI+SLLI+ADDI+SLLI+ADDI) has to be emitted. Note that the first two instructions (LUI+ADDIW) can contribute up to 32 bits while the following ADDI instructions contribute up to 12 bits each.*

*On the first glance, implementing this seems to be possible by simply emitting the most significant 32 bits (LUI+ADDIW) followed by as many left shift (SLLI) and immediate additions (ADDI) as needed. However, due to the fact that ADDI performs a sign extended addition, doing it like that would only be possible when at most 11 bits of the ADDI instructions are used. Using all 12 bits of the ADDI instructions, like done by GAS, actually requires that the constant is processed starting with the least significant bit.*

*In the following, constants are processed from LSB to MSB but instruction emission is performed from MSB to LSB by recursively calling `generateInstSeq`. In each recursion, first the lowest 12 bits are removed from the constant and the optimal shift amount, which can be greater than 12 bits if the constant is sparse, is determined. Then, the shifted remaining constant is processed recursively and gets emitted as soon as it fits into 32 bits. The emission of the shifts and additions is subsequently performed when the recursion returns.*



```smalltalk
recursiveLoadImmediate: anImmediate inRegister: aRegister andEmitInstructionsIn: aCollection

	"LLVM uses a clever recursive way to determine the best combination of instructions that
	 are needed by the pseudo instruction li.
	https://github.com/llvm/llvm-project/blob/4c3d916c4bd2a392101c74dd270bd1e6a4fec15b/llvm/lib/Target/RISCV/MCTargetDesc/RISCVMatInt.cpp"

	| hi20 lo12 hi52 shiftAmount signedImmediate |
	self flag: #TODO.
	signedImmediate := anImmediate signedIntFromLong64.
	"Special case if the value is 16rFFFFFFFFFFFFFFFF (max)"
	(signedImmediate = -1)
		ifTrue: [ aCollection add: (self addImmediate: -1 toRegister: X0 inRegister: aRegister).
					 "End the recursion!"
					 ^ 0 ].
	"Check if the immediate can be contained in 32 bits"		
	(self value: signedImmediate isContainedIn: 31)
		ifTrue: [
			"Depending on the value of the immediate, the following instructions are emitted:
				imm == 0                          : ADDI
				imm[0,12) != 0 && imm[12,32) == 0 : ADDI
			   imm[0,12) == 0 && imm[12,32) != 0 : LUI
				imm[0,32) != 0                    : LUI+ADDIW
			"
			hi20 := (((self computeSignedValue64Bits: signedImmediate) + 16r800) >> 12) bitAnd: 16rFFFFF.
			lo12 := self computeSignedValue64Bits: (signedImmediate bitAnd: 16rFFF).

			"lui instruction"
			hi20 ~= 0
				ifTrue: [ aCollection add: (self loadUpperImmediate: hi20 inRegister: aRegister) ].

			((lo12 ~= 0) or: [hi20 = 0])
				ifTrue: [ hi20 ~= 0
						ifTrue: [ aCollection add: (self addWordImmediate: lo12 toRegister: aRegister inRegister: aRegister)]
						ifFalse: [ aCollection add: (self addImmediate: lo12 toRegister: X0 inRegister: aRegister) ]
					].
			"Return to end the recursion"			
			^ 0
		].
		"In the case the value does not fit in 32 bits"
		lo12 := self computeSignedValue64Bits: (signedImmediate bitAnd: 16rFFF).
		hi52 := (((self computeSignedValue64Bits: signedImmediate) + 16r800) bitAnd: 16rFFFFFFFFFFFFFFFF) >> 12.
		"Process the optimal shift amount"
		shiftAmount := 12 + (self trailingZerosOf: hi52).
		hi52 := self computeSignedValueOf: hi52 >> (shiftAmount - 12) ofSize: (64 - shiftAmount).

		"Check if the shift amount can be reduced to fit in a 32 bit variable"
		((shiftAmount > 12) and: [((hi52 bitAnd: 16rFFF) = 0) and: [self value: (hi52 << 12) isContainedIn: 32]])
			ifTrue: [
				"Reduce the shift amount"  
				shiftAmount := shiftAmount - 12.
				hi52 := self computeSignedValueOf: hi52 << 12 ofSize: 64.
			].

		" Recursive call"
		self recursiveLoadImmediate: hi52 inRegister: aRegister andEmitInstructionsIn: aCollection.
		"Add shift and add"		
		aCollection add: (self shiftLeftValueInRegister: aRegister byShiftAmount: shiftAmount intoRegister: aRegister).
		lo12 ~= 0
			ifTrue: [ aCollection add: (self addImmediate: lo12 toRegister: aRegister inRegister: aRegister) ].

		^ 0

```
