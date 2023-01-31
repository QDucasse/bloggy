---
title: "Debugging Pharo JIT code in gdb"
date: "2022-03-10"
tags: [
    "pharo",
    "jit",
    "gdb",
]
categories: [
    "Guide"
]
---

Investigating VM runtime crashes can be obscure, especially when dealing with code that has been recompiled to machine code by the JIT compiler. This post will show the way to track the execution path within `gdb`. Note that you will need `gdb` to be available to debug the VM, it is not possible to do this through a simple `qemu` image (at least by default) or user-space simulation such as `qemu-debootstrap`. The solution is to debug directly on the hardware (provided it exists!).

## Pharo VM Compilation

The Pharo VM is a **meta-circular VM** written in the language it aims to execute (here SmallTalk!). This means that the VM code can all be inspected and executed in the Pharo environment. However, to generate an actual executable, the VM code is translated by **Slang, a Smalltalk-to-C transpiler**. The translation is only made possible due to the fact that the VM Smalltalk code is **written in a restricted SmallTalk and annotated** so that most of the ambiguity is cleared. Once the code is translated, it can be compiled down to an executable. Two flavors are available: the **`StackVM`** that only has the interpreter and the **`CoInterpreter`** that has the Cogit JIT compiler. Hitting against a `SEGFAULT` at runtime raises questions at several levels: issues in the *translation*? issues in the *build*? issues in the *runtime environment*?

## Running the Pharo VM through `gdb`

To provide an example, we will trigger a `SEGFAULT` in the x86 Pharo VM. Let's get our hands on a fresh Pharo VM and image. Several are available at http://getpharo.org/ and can be obtained with:

```bash
$ mkdir getpharo; cd getpharo
$ curl https://get.pharo.org | bash # or wget -O- https://get.pharo.org | bash
```

The first step is to launch the Pharo VM with `gdb`. This can be done with:

```bash
$ ./pharo-ui -gdb
(gdb) r Pharo.image
```

This should open a Pharo environment and you can see the different threads launched in `gdb`:

```bash
[New Thread 0x7ffff76b3700 (LWP 43777)]
[New Thread 0x7ffff49b6700 (LWP 43778)]
[New Thread 0x7fffec06b700 (LWP 43779)]
[New Thread 0x7fffeb818700 (LWP 43780)]
...
```

## Triggering a `SEGFAULT`

From within the Pharo environment, we can trigger a `SEGFAULT` by defining an external address to some random number and reading it. This can be done by opening a playground and writing:

```smalltalk
(ExternalAddress fromAddress: 1234567) readStringUTF8
```

Pressing `Ctrl-D` will trigger the `SEGFAULT`, freeze the image and bring the control back to `gdb`.



> Note: It can also be triggered as a standalone script that contains the line from the playground using:
>
> ```
> (gdb) r --headless Pharo.image segfault.st
> ```



## Inspecting the call stack

Running through gdb and inspecting the call stack through `bt` (stands for backtrace). In our case, we can see:

```java
(gdb) bt
#0  primitiveLoadUInt8FromExternalAddress ()
	at /builds/workspace/pharo-vm_pharo-9/build-stockReplacement/generated/64/vm/src/gcc3x-cointerp.c:15026
#1  0x00007ffff7ce12a2 in interpret ()
	at /builds/workspace/pharo-vm_pharo-9/build-stockReplacement/generated/64/vm/src/gcc3x-cointerp.c:6253
#2  0x00007ffff7ce6b02 in enterSmalltalkExecutiveImplementation ()
	at /builds/workspace/pharo-vm_pharo-9/build-stockReplacement/generated/64/vm/src/gcc3x-cointerp.c:17418
#3  0x00007ffff7cd9a76 in interpret ()
	at /builds/workspace/pharo-vm_pharo-9/build-stockReplacement/generated/64/vm/src/gcc3x-cointerp.c:2986
#4  0x00007ffff7c51c25 in vm_run_interpreter ()
	at /builds/workspace/pharo-vm_pharo-9/repository/src/client.c:90
#5  0x00007ffff7c51c7e in runVMThread (p=p@entry=0x7fffffffd530)
	at /builds/workspace/pharo-vm_pharo-9/repository/src/client.c:253
#6  0x00007ffff7c51f17 in runOnMainThread (parameters=0x7fffffffd530)
	at /builds/workspace/pharo-vm_pharo-9/repository/src/client.c:261
#7  vm_main_with_parameters (parameters=0x7fffffffd530)
	at /builds/workspace/pharo-vm_pharo-9/repository/src/client.c:151
#8  0x00007ffff7c521a8 in vm_main (argc=<optimized out>, argv=<optimized out>, env=<optimized out>)
	at /builds/workspace/pharo-vm_pharo-9/repository/src/client.c:204
#9  0x00007ffff7a5e0b3 in __libc_start_main (main=0x4005e0 <main>, argc=2, argv=0x7fffffffd6a8,
											 init=<optimized out>, fini=<optimized out>, rtld_fini=<optimized out>,
											 stack_end=0x7fffffffd698)
	at ../csu/libc-start.c:308
#10 0x0000000000400619 in _start ()

```

Now we can also look at the call stack on the Pharo side with the method (translated to C!) `printCallStack()`:

```java
(gdb) p printCallStack()
    0x7ffffffc8308 I ExternalAddress>unsignedByteAt: 0x693dfd8: a(n) ExternalAddress
    0x7ffffffc8368 I ExternalData>readStringUTF8 0x693e250: a(n) ExternalData
    0x7ffffffc83a8 I ExternalAddress(ByteArray)>readStringUTF8 0x693dfd8: a(n) ExternalAddress
    0x7ffffffc83d8 M UndefinedObject>DoIt 0x6b43c00: a(n) UndefinedObject
    0x7ffffffc8408 M [] in OpalCompiler>evaluate 0x69129e0: a(n) OpalCompiler
    0x7ffffffc8438 M FullBlockClosure(BlockClosure)>on:do: 0x6913f48: a(n) FullBlockClosure
    0x7ffffffc8490 I OpalCompiler>evaluate 0x69129e0: a(n) OpalCompiler
    ...


```

What do we get from those? From the OS side, the application triggered a `SEGFAULT` in the **interpretation loop** when calling a primitive. From the Pharo side, the call stack can be deciphered as a succession of frames where each present:

- The **address** they are located at (starting with `0x7fffff...`)
- An **identifier** (**I** for **Interpreted**, **M** for **Machine code** and **S** for **Single**)
- The **method class** and **name** (note that in the case of blocks it presents `[]`)
- The **address of the receiver**
- The **type of the receiver**



## Diving in a Frame

Now that we have the big picture of what is happening in the call stack, let's look into a frame in more detail. The one we will dive into is:

```java
0x7ffffffc83d8 M UndefinedObject>DoIt 0x6b43c00: a(n) UndefinedObject
```

We can print all the information it holds by using the method (translated to C once again!) `printFrame()`:

```java
(gdb) p printFrame(0x7ffffffc83d8)
    0x7ffffffc83d8 M UndefinedObject>DoIt 0x6b43c00: a(n) UndefinedObject
    0x7ffffffc83e8:   rcvr/clsr:          0x6b43c00	=nil
    0x7ffffffc83e0:   caller ip:          0x551e475=89252981
    0x7ffffffc83d8:    saved fp:     0x7ffffffc8408=140737488126984
    0x7ffffffc83d0:      method:          0x553e308	0x692cf10: a(n) CompiledMethod
    0x7ffffffc83d0: mcfrm flags:                0x0  numArgs: 0 noContext notBlock
    0x7ffffffc83c8:     context:          0x6b43c00	=nil
    0x7ffffffc83c0:    receiver:          0x6b43c00	=nil
    0x7ffffffc83b0:    frame pc:          0x553e3c5=89383877
```

A frame holds a lot of information such as the **caller instruction pointer**, the **receiver**, the **frame instruction pointer** and the **method itself**. This is from the frame that holds the `DoIt` method which takes no argument and was identified with **M**. If we compare it with for example:

```java
0x7ffffffc8308 I ExternalAddress>unsignedByteAt: 0x693dfd8: a(n) ExternalAddress
```

This frame holds the method `unsignedByteAt:` which takes one argument and the **I** identifier. Printing the frame shows:

```java
(gdb) p printFrame(0x7ffffffc8308)
    0x7ffffffc8308 I ExternalAddress>unsignedByteAt: 0x693dfd8: a(n) ExternalAddress
    0x7ffffffc8320:   rcvr/clsr:          0x693dfd8	=a(n) ExternalAddress
    0x7ffffffc8318:        arg0:                0x9	=1(0x1)
    0x7ffffffc8310:   caller ip:          0x884a9dc=142911964
    0x7ffffffc8308:    saved fp:     0x7ffffffc8368=140737488126824
    0x7ffffffc8300:      method:          0x88473c8	0x88473c8: a(n) CompiledMethod
    0x7ffffffc82f8:     context:          0x6b43c00	=nil
    0x7ffffffc82f0:intfrm flags:              0x101=257  numArgs: 1 noContext notBlock
    0x7ffffffc82e8:    saved ip:                0x0 0
    0x7ffffffc82e0:    receiver:          0x693dfd8	=a(n) ExternalAddress
    0x7ffffffc82d8:        stck:          0x693dfd8	=a(n) ExternalAddress
    0x7ffffffc82d0:        stck:                0x1	=0(0x0)
```

This time, an `arg0` field can be found as well as a receiver and the flags field has changed from **m**a**c**hine code flags to **int**erpreter flags.



## Extracting the method information

To find if a method is a machine code method, the function `methodFor(<method_address>)`  can output either the **location of the machine code** or `NULL` if it is not a machine code method. In the two cases presented earlier, the outputs are:

```java
(gdb) p methodFor(0x553e308) # frame DoIt
	(CogMethod *) 0x553e308
(gdb) p methodFor(0x88473c8) # frame unsignedByteAt:
    (CogMethod *) 0x0
```

Using this information, we can use another print to get more information from the machine code method, `printCogMethod(<cog_method_pointer>)`:

```java
(gdb) p printCogMethod((CogMethod *) 0x553e308)
0x553e308 <->          0x553e3d8: method:          0x692cf10 selector:          0x6b43c00 (nil: DoIt)
 <-> 0x553e3d8:   method: 0x692cf10   selector: 0x6b43c00 (nil: DoIt)
```

This output presents:

- The **start of the machine code method**

- The **end of the machine code method**

- The **location of the compiled method** (in bytecodes)

  > Note: This could be seen in the frame description side by side with its machine code one, and the two are identical in the case of a method that has not been recompiled which is the case for the second frame!

- The **location of the selector** (here it is `nil`)

- If it is a **primitive**, its id is printed as well



When compiling a method to machine code it is split into 3 parts: **header metadata** (size depends on the machine), the **machine code** itself and **more metadata**. To disassemble the correct part, we need to go over the header. Its size can be found with the `cmEntryOffset` and `cmNoCheckEntryOffset` methods. In our case:

```java
(gdb) print cmEntryOffset
	48
(gdb) print cmNoCheckEntryOffset
	74
```



## Disassembling the JITed method

Now that we have the address of the JITed method as well as the offset size, we can disassemble it with the `disassemble` instruction from `gdb`. We need to pass it the address with the offset added as well as end address (can be an offset from the start address starting with a +):

```java
(gdb) disassemble 0x553e308+48,+150
Dump of assembler code from 0x553e338 to 0x553e3ce:
   0x000000000553e338:	mov    %rdx,%rax
   0x000000000553e33b:	and    $0x7,%rax
   0x000000000553e33f:	jne    0x553e34d
   0x000000000553e341:	mov    (%rdx),%rax
   0x000000000553e344:	and    $0x3fffff,%rax
   0x000000000553e34a:	nop
   0x000000000553e34b:	nop
   0x000000000553e34c:	nop
   0x000000000553e34d:	cmp    %rcx,%rax
   0x000000000553e350:	jne    0x553e333
   0x000000000553e352:	mov    (%rsp),%r9
   0x000000000553e356:	mov    %rdx,(%rsp)
   0x000000000553e35a:	push   %r9
   0x000000000553e35c:	push   %rbp
   0x000000000553e35d:	mov    %rsp,%rbp
   0x000000000553e360:	lea    -0x5f(%rip),%r8        # 0x553e308
   0x000000000553e367:	push   %r8
   0x000000000553e369:	mov    $0x6b43c00,%r9
   0x000000000553e370:	push   %r9
   0x000000000553e372:	push   %rdx
   0x000000000553e373:	movabs 0x7ffff7f391f8,%rax
   0x000000000553e37d:	cmp    %rax,%rsp
   0x000000000553e380:	jb     0x553e330
   0x000000000553e382:	movabs $0x6bcb408,%rax
   0x000000000553e38c:	nop
   0x000000000553e38d:	mov    (%rax),%r15
   0x000000000553e390:	and    $0x3ffff7,%r15
   0x000000000553e397:	jne    0x553e39f
   0x000000000553e399:	mov    0x8(%rax),%rax
   0x000000000553e39d:	jmp    0x553e38d
   0x000000000553e39f:	mov    0x10(%rax),%r15
   0x000000000553e3a3:	mov    $0x96b439,%rdi
   0x000000000553e3aa:	mov    %r15,%rdx
   0x000000000553e3ad:	mov    $0x2,%rcx
   0x000000000553e3b4:	callq  0x53ee0c0
   0x000000000553e3b9:	mov    $0x3,%rcx
   0x000000000553e3c0:	callq  0x53ee080
   0x000000000553e3c5:	mov    %rbp,%rsp
   0x000000000553e3c8:	pop    %rbp
   0x000000000553e3c9:	retq   $0x8
   0x000000000553e3cc:	int3   
   0x000000000553e3cd:	int3   
End of assembler dump.
```

This is the routine of our Cog method. The usual routine works as follows:

- **Abort routine**

- **Entry point** and **type check**
- **Frame building**
- **Stack overflow** and maybe **context switch**
- **Message send**
- **Frame un-building** and **return**



To see those steps in our methods, we can look at what the different calls are pointing at, that should be different **trampolines**. To print trampoline info, using `printTrampolineTable()` will show the **addresses and names** of the ones known by the JIT compiler.

```java
(gdb) p printTrampolineTable()
	     0x53ee000: ceGetFP
         0x53ee008: ceGetSP
         0x53ee010: ceCaptureCStackPointers
         0x53ee030: ceDereferenceSelectorIndex
         0x53ee080: ceSend0Args
         0x53ee0c0: ceSend1Args
         0x53ee108: ceSend2Args
         0x53ee150: ceSendNArgs
         ...
         0x53ef5d8: ceCallPIC0Args
         0x53ef5f8: ceCallPIC1Args
         0x53ef618: ceCallPIC2Args
         0x53ef638: ceTraceLinkedSendTrampoline
         0x53ef680: ceTraceBlockActivationTrampoline
         0x53ef6c8: ceTraceStoreTrampoline
         0x53ef710: methodZoneBase
```

> Note: The `ce` prefix means call execution



Linking the trampolines to the different calls and looking into the jumps of our method we can annotate it as:

```java
Dump of assembler code from 0x553e338 to 0x553e3ce:
____________________________________________________________________________________________________
Entry point and type check
____________________________________________________________________________________________________
   0x000000000553e338:	mov    %rdx,%rax
   0x000000000553e33b:	and    $0x7,%rax
   0x000000000553e33f:	jne    0x553e34d            <-- Jump over the next type check
   0x000000000553e341:	mov    (%rdx),%rax
   0x000000000553e344:	and    $0x3fffff,%rax
   0x000000000553e34a:	nop
   0x000000000553e34b:	nop
   0x000000000553e34c:	nop
   0x000000000553e34d:	cmp    %rcx,%rax
   0x000000000553e350:	jne    0x553e333            <-- Jump to the abort routine before the entry
 ____________________________________________________________________________________________________
 Frame building
 ____________________________________________________________________________________________________
   0x000000000553e352:	mov    (%rsp),%r9
   0x000000000553e356:	mov    %rdx,(%rsp)
   0x000000000553e35a:	push   %r9
   0x000000000553e35c:	push   %rbp
   0x000000000553e35d:	mov    %rsp,%rbp
   0x000000000553e360:	lea    -0x5f(%rip),%r8        # 0x553e308
   0x000000000553e367:	push   %r8
   0x000000000553e369:	mov    $0x6b43c00,%r9
   0x000000000553e370:	push   %r9
   0x000000000553e372:	push   %rdx
____________________________________________________________________________________________________
Stack overflow and maybe context change
____________________________________________________________________________________________________
   0x000000000553e373:	movabs 0x7ffff7f391f8,%rax
   0x000000000553e37d:	cmp    %rax,%rsp
   0x000000000553e380:	jb     0x553e330            <-- Jump to the abort routine before the entry
   0x000000000553e382:	movabs $0x6bcb408,%rax
   0x000000000553e38c:	nop
   0x000000000553e38d:	mov    (%rax),%r15
   0x000000000553e390:	and    $0x3ffff7,%r15
   0x000000000553e397:	jne    0x553e39f            <-- Jump over next move
   0x000000000553e399:	mov    0x8(%rax),%rax
   0x000000000553e39d:	jmp    0x553e38d            <-- Jump back to check again
____________________________________________________________________________________________________
Message sends
____________________________________________________________________________________________________
   0x000000000553e39f:	mov    0x10(%rax),%r15    
   0x000000000553e3a3:	mov    $0x96b439,%rdi      <-- Our fake address 1234567
   0x000000000553e3aa:	mov    %r15,%rdx
   0x000000000553e3ad:	mov    $0x2,%rcx
   0x000000000553e3b4:	callq  0x53ee0c0           <-- Trampoline ceSend1Args unsignedByteAt:
   0x000000000553e3b9:	mov    $0x3,%rcx
   0x000000000553e3c0:	callq  0x53ee080		   <-- Trampoline ceSend0Args DoIt
____________________________________________________________________________________________________
Frame unbuilding and ret
____________________________________________________________________________________________________
   0x000000000553e3c5:	mov    %rbp,%rsp
   0x000000000553e3c8:	pop    %rbp
   0x000000000553e3c9:	retq   $0x8
   0x000000000553e3cc:	int3   
   0x000000000553e3cd:	int3   
End of assembler dump.
```

The most important part of this is the `Message sends`. If we look at what this part looks in the JIT intermediate representation `CogRTL`, it is presented as:

```c
MoveRR                <receiver>       ReceiverResultReg
MovePatcheableC32R    <selector index> ClassReg
Call                  <trampoline>
```

This is the initial state of a JITed method, however the objective is to redirect it to the correct method by patching it into a monomorphic call for example:

```C
MoveRR                <receiver>                       ReceiverResultReg
MovePatcheableC32R    <expected class of the receiver> ClassReg
Call                  <jited method address>
```

That can itself be patched again to a polymorphic call by redirecting the cal to a small piece of logic:

```C
MoveRR                <receiver>                       ReceiverResultReg
MovePatcheableC32R    <expected class of the receiver> ClassReg
Call                  <polymorphic call logic>
```



## Inspecting trampolines

The trampolines can be inspected too by disassembling them the same way it is done for methods. Looking around the `ceSend0Args(0x53ee080)`:

```java
(gdb) disassemble 0x53ee080,+70
Dump of assembler code from 0x53ee080 to 0x53ee0c6:
   0x00000000053ee080:	mov    (%rsp),%r9                <-- ceSend0Args
   0x00000000053ee084:	mov    %rdx,(%rsp)
   0x00000000053ee088:	push   %r9
   0x00000000053ee08a:	callq  0x53ee030
   0x00000000053ee08f:	mov    %rbp,0x30(%rbx)
   0x00000000053ee093:	mov    %rsp,0x40(%rbx)
   0x00000000053ee097:	mov    0x8d608(%rbx),%rsp
   0x00000000053ee09e:	mov    %rcx,%rdi
   0x00000000053ee0a1:	xor    %rsi,%rsi
   0x00000000053ee0a4:	xor    %rcx,%rcx
   0x00000000053ee0a7:	movabs $0x7ffff7cd79c0,%rax
   0x00000000053ee0b1:	callq  *%rax
   0x00000000053ee0b3:	mov    0x40(%rbx),%rsp
   0x00000000053ee0b7:	mov    0x30(%rbx),%rbp
   0x00000000053ee0bb:	retq   
   0x00000000053ee0bc:	int3   
   0x00000000053ee0bd:	int3   
   0x00000000053ee0be:	int3   
   0x00000000053ee0bf:	int3   
   0x00000000053ee0c0:	mov    (%rsp),%r9	            <-- ceSend1Args
   0x00000000053ee0c4:	mov    %rdx,(%rsp)
End of assembler dump.

```
