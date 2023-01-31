---
title: "Cogit runtime trampolines"
date: "2022-04-04"
tags: [
    "pharo",
    "jit",
		"trampoline"
]
categories: [
    "Exploration"
]
---


## `Cogit` trampolines

`cePICMissTrampoline`

`ceCallCogCodePopReceiverAndClassRegs`

`ceCallCogCodePopReceiverReg`

`ceCannotResumeTrampoline`

`ceCaptureCStackPointers`

`ceCheckFeaturesFunction`

`ceCheckForInterruptTrampoline`

`ceEnclosingObjectTrampoline`

`ceEnterCogCodePopReceiverReg`

`ceFetchContextInstVarTrampoline`

`ceFlushICache`

`ceFreeTrampoline`

`ceGetFP`

`ceGetSP`

`ceMallocTrampoline`

`ceMethodAbortTrampoline`

`ceNonLocalReturnTrampoline`

`cePICAbortTrampoline`

`cePrimReturnEnterCogCode`

`cePrimReturnEnterCogCodeProfiling`

`ceReapAndResetErrorCodeTrampoline`

`ceReturnToInterpreterTrampoline`

`ceSendMustBeBooleanAddFalseTrampoline`

`ceSendMustBeBooleanAddTrueTrampoline`

`ceStoreContextInstVarTrampoline`

`ceTraceBlockActivationTrampoline`

`ceTraceLinkedSendTrampoline`

`ceTraceStoreTrampoline`

`ceTryLockVMOwner`

`ceUnlockVMOwner`



## `SimpleStackBasedCogit` trampolines

`ceCPICMissTrampoline`

`ceCheckForInterruptTrampoline`

`ceEnclosingObjectTrampoline`

`ceFetchContextInstVarTrampoline`

`ceMethodAbortTrampoline`

`ceNonLocalReturnTrampoline`

`cePICAbortTrampoline`

`cePrimReturnEnterCogCode`

`cePrimReturnEnterCogCodeProfiling`

`ceReapAndResetErrorCodeTrampoline`

`ceStoreContextInstVarTrampoline`

`ceTraceBlockActivationTrampoline`

`ceTraceLinkedSendTrampoline`

`ceTraceStoreTrampoline`



## `StackToRegisterMappingCogit` trampolines

`ceEnclosingObjectTrampoline`

`ceFetchContextInstVarTrampoline`

`ceNonLocalReturnTrampoline`

`ceReapAndResetErrorCodeTrampoline`

`ceStoreContextInstVarTrampoline`

`ceTraceBlockActivationTrampoline`

`ceTraceLinkedSendTrampoline`

`ceTraceStoreTrampoline`



## `RegisterAllocatingCogit` trampolines

`ceCheckForInterruptTrampoline`

`ceSendMustBeBooleanAddFalseTrampoline`

`ceSendMustBeBooleanAddTrueTrampoline`



## Trampoline generation

```smalltalk
generateTrampolines
	"Generate the run-time entries and exits at the base of the native code zone and update the base.
	 Read the class-side method trampolines for documentation on the various trampolines"
	| methodZoneStart |

	methodZoneStart := methodZoneBase.
	methodLabel address: methodZoneStart.
	self allocateOpcodes: 80 bytecodes: 0.
	hasYoungReferent := false.

	self
		enableCodeZoneWriteDuring: [ 	
			objectRepresentation maybeGenerateSelectorIndexDereferenceRoutine.
			self generateSendTrampolines.                        "Send variations"
			self generateMissAbortTrampolines.                   "PIC Miss/Abort"
			objectRepresentation generateObjectRepresentationTrampolines.
			self generateRunTimeTrampolines.                     "Runtime"
			self generateEnilopmarts.                            "Enilopmarts (machine code to C)"
			self generateTracingTrampolines.                     "Tracing methods"
			self recordGeneratedRunTime: 'methodZoneBase' address: methodZoneBase]
		flushingCacheWith: [ self flushICacheFrom: methodZoneStart asUnsignedInteger to: methodZoneBase asUnsignedInteger ].
```



#### Selector Dereference

```bash
0x6a03000: ceGetFP
0x6a03008: ceGetSP
0x6a03010: ceCaptureCStackPointers
0x6a03080: ceDereferenceSelectorIndex
```



#### Send trampolines

```smalltalk
generateSendTrampolines
	0 to: NumSendTrampolines - 1 do:
		[:numArgs|
		ordinarySendTrampolines
			at: numArgs
			put: (self genTrampolineFor: #ceSend:super:to:numArgs:
					  called: (self trampolineName: 'ceSend' numArgs: numArgs)
					  arg: ClassReg
					  arg: (self trampolineArgConstant: false)
					  arg: ReceiverResultReg
					  arg: (self numArgsOrSendNumArgsReg: numArgs))].

	"Generate these in the middle so they are within [firstSend, lastSend]."
	BytecodeSetHasDirectedSuperSend ifTrue:
		[0 to: NumSendTrampolines - 1 do:
			[:numArgs|
			directedSuperSendTrampolines
				at: numArgs
				put: (self genTrampolineFor: #ceSend:above:to:numArgs:
						  called: (self trampolineName: 'ceDirectedSuperSend' numArgs: numArgs)
						  arg: ClassReg
						  arg: TempReg
						  arg: ReceiverResultReg
						  arg: (self numArgsOrSendNumArgsReg: numArgs)).
			directedSuperBindingSendTrampolines
				at: numArgs
				put: (self genTrampolineFor: #ceSend:aboveClassBinding:to:numArgs:
						  called: (self trampolineName: 'ceDirectedSuperBindingSend' numArgs: numArgs)
						  arg: ClassReg
						  arg: TempReg
						  arg: ReceiverResultReg
						  arg: (self numArgsOrSendNumArgsReg: numArgs))]].

	0 to: NumSendTrampolines - 1 do:
		[:numArgs|
		superSendTrampolines
			at: numArgs
			put: (self genTrampolineFor: #ceSend:super:to:numArgs:
					  called: (self trampolineName: 'ceSuperSend' numArgs: numArgs)
					  arg: ClassReg
					  arg: (self trampolineArgConstant: true)
					  arg: ReceiverResultReg
					  arg: (self numArgsOrSendNumArgsReg: numArgs))].
	firstSend := ordinarySendTrampolines at: 0.
	lastSend := superSendTrampolines at: NumSendTrampolines - 1
```

```bash
0x6a031c0: ceSend0Args
0x6a03250: ceSend1Args
0x6a032e8: ceSend2Args
0x6a03388: ceSendNArgs
0x6a03410: ceDirectedSuperSend0Args
0x6a034a0: ceDirectedSuperBindingSend0Args
0x6a03530: ceDirectedSuperSend1Args
0x6a035c8: ceDirectedSuperBindingSend1Args
0x6a03660: ceDirectedSuperSend2Args
0x6a03700: ceDirectedSuperBindingSend2Args
0x6a037a0: ceDirectedSuperSendNArgs
0x6a03828: ceDirectedSuperBindingSendNArgs
0x6a038b0: ceSuperSend0Args
0x6a03940: ceSuperSend1Args
0x6a039d8: ceSuperSend2Args
0x6a03a78: ceSuperSendNArgs
```



#### PIC Miss/Abort trampolines



```smalltalk
generateMissAbortTrampolines
	"Generate the run-time entries for the various method and PIC entry misses and aborts.
	 Read the class-side method trampolines for documentation on the various trampolines"
	0 to: self numRegArgs + 1 do:
		[:numArgs|
		methodAbortTrampolines
			at: numArgs
			put: (self genMethodAbortTrampolineFor: numArgs)].
	0 to: self numRegArgs + 1 do:
		[:numArgs|
		picAbortTrampolines
			at: numArgs
			put: (self genPICAbortTrampolineFor: numArgs)].
	0 to: self numRegArgs + 1 do:
		[:numArgs|
		picMissTrampolines
			at: numArgs
			put: (self genPICMissTrampolineFor: numArgs)].
	ceReapAndResetErrorCodeTrampoline := self genTrampolineFor: #ceReapAndResetErrorCodeFor:
												called: 'ceReapAndResetErrorCodeTrampoline'
												arg: ClassReg
```



```bash
0x6a03b00: ceMethodAbort0Args
0x6a03be0: ceMethodAbort1Args
0x6a03cc8: ceMethodAbort2Args
0x6a03db8: ceMethodAbortNArgs
0x6a03e88: cePICAbort0Args
0x6a03f68: cePICAbort1Args
0x6a04050: cePICAbort2Args
0x6a04140: cePICAbortNArgs
0x6a04210: cePICMiss0Args
0x6a04280: cePICMiss1Args
0x6a042f8: cePICMiss2Args
0x6a04378: cePICMissNArgs
0x6a043e0: ceReapAndResetErrorCodeTrampoline
```

#### Object Representation trampolines

```smalltalk
generateObjectRepresentationTrampolines
	"Do the store check.  Answer the argument for the benefit of the code generator;
	 ReceiverResultReg may be caller-saved and hence smashed by this call.  Answering
	 it allows the code generator to reload ReceiverResultReg cheaply.
	 In Spur the only thing we leave to the run-time is adding the receiver to the
	 remembered set and setting its isRemembered bit."
	self
		cppIf: IMMUTABILITY
		ifTrue:
			[self cCode: [] inSmalltalk:
				[ceStoreTrampolines := CArrayAccessor on: (Array new: NumStoreTrampolines)].
			 0 to: NumStoreTrampolines - 1 do:
				[:instVarIndex |
				 ceStoreTrampolines
					at: instVarIndex
					put: (self
							genStoreTrampolineCalled: (cogit
								trampolineName: 'ceStoreTrampoline'
								numArgs: instVarIndex
								limit: NumStoreTrampolines - 2)
							instVarIndex: instVarIndex)]].
	ceNewHashTrampoline := self genNewHashTrampoline: false called: 'ceNewHash'.
	SistaVM ifTrue: [ceInlineNewHashTrampoline := self genNewHashTrampoline: true  called: 'ceInlineNewHash'].
	ceStoreCheckTrampoline := self genStoreCheckTrampoline.
	ceStoreCheckContextReceiverTrampoline := self genStoreCheckContextReceiverTrampoline.
	ceScheduleScavengeTrampoline := cogit
		genTrampolineFor: #ceScheduleScavenge
		called: 'ceScheduleScavengeTrampoline'
		regsToSave: CallerSavedRegisterMask.
	ceSmallActiveContextInMethodTrampoline := self
    	genActiveContextTrampolineLarge: false
        inBlock: 0
        called: 'ceSmallMethodContext'.
	ceSmallActiveContextInBlockTrampoline := self
    	genActiveContextTrampolineLarge: false
        inBlock: InVanillaBlock
        called: 'ceSmallBlockContext'.
	SistaV1BytecodeSet ifTrue:
		[ceSmallActiveContextInFullBlockTrampoline := self
        	genActiveContextTrampolineLarge: false
            inBlock: InFullBlock
            called: 'ceSmallFullBlockContext'].
	ceLargeActiveContextInMethodTrampoline := self
    	genActiveContextTrampolineLarge: true
        inBlock: 0
        called: 'ceLargeMethodContext'.
	ceLargeActiveContextInBlockTrampoline := self
    	genActiveContextTrampolineLarge: true
        inBlock: InVanillaBlock
        called: 'ceLargeBlockContext'.
	SistaV1BytecodeSet ifTrue:
		[ceLargeActiveContextInFullBlockTrampoline := self
        	genActiveContextTrampolineLarge: true
            inBlock: InFullBlock
            called: 'ceLargeFullBlockContext'].
```



```
0x6a04448: ceStoreTrampoline0Args
0x6a04538: ceStoreTrampoline1Args
0x6a04628: ceStoreTrampoline2Args
0x6a04718: ceStoreTrampoline3Args
0x6a04808: ceStoreTrampolineNArgs
0x6a048f8: ceNewHash
0x6a04960: ceStoreCheckTrampoline
0x6a049e8: ceStoreCheckContextReceiver
0x6a04a90: ceScheduleScavengeTrampoline
0x6a04b10: ceSmallMethodContext
0x6a04ec8: ceSmallBlockContext
0x6a052d0: ceSmallFullBlockContext
0x6a056b0: ceLargeMethodContext
0x6a05a68: ceLargeBlockContext
0x6a05e70: ceLargeFullBlockContext
```



#### Runtime trampolines



```smalltalk
generateRunTimeTrampolines
	"Generate the run-time entries at the base of the native code zone and update the base."

	ceSendMustBeBooleanAddFalseTrampoline := self genMustBeBooleanTrampolineFor: objectMemory falseObject
												  called: 'ceSendMustBeBooleanAddFalseTrampoline'.
	ceSendMustBeBooleanAddTrueTrampoline := self genMustBeBooleanTrampolineFor: objectMemory trueObject
												 called: 'ceSendMustBeBooleanAddTrueTrampoline'.
	ceNonLocalReturnTrampoline := self genNonLocalReturnTrampoline.
	ceCheckForInterruptTrampoline := self genCheckForInterruptsTrampoline.
	"Neither of the context inst var access trampolines save registers.  Their operation could cause
	 arbitrary update of stack frames, so the assumption is that callers flush the stack before calling
	 the context inst var access trampolines, and that everything except the result is dead afterwards."
	ceFetchContextInstVarTrampoline := self genTrampolineFor: #ceContext:instVar:
											called: 'ceFetchContextInstVarTrampoline'
											arg: ReceiverResultReg
											arg: SendNumArgsReg
											result: SendNumArgsReg.
	ceStoreContextInstVarTrampoline := self genTrampolineFor: #ceContext:instVar:value:
											called: 'ceStoreContextInstVarTrampoline'
											arg: ReceiverResultReg
											arg: SendNumArgsReg
											arg: ClassReg
											result: ReceiverResultReg. "to keep ReceiverResultReg live.".
	ceCannotResumeTrampoline := self genTrampolineFor: #ceCannotResume
									 called: 'ceCannotResumeTrampoline'.
	"These two are unusual; they are reached by return instructions."
	ceBaseFrameReturnTrampoline := self genReturnTrampolineFor: #ceBaseFrameReturn:
										called: 'ceBaseFrameReturnTrampoline'
										arg: ReceiverResultReg.
	ceReturnToInterpreterTrampoline := self genReturnTrampolineFor: #ceReturnToInterpreter:
											called: 'ceReturnToInterpreterTrampoline'
											arg: ReceiverResultReg.
	ceMallocTrampoline := self genTrampolineFor: #ceMalloc:
							   called: 'ceMallocTrampoline'
							   arg: ReceiverResultReg
						       result: TempReg.
	ceFreeTrampoline := self genTrampolineFor: #ceFree:
						 	 called: 'ceFreeTrampoline'
							 arg: ReceiverResultReg.
```



```bash
0x6a06250: ceSendMustBeBooleanAddFalseTrampoline
0x6a062e8: ceSendMustBeBooleanAddTrueTrampoline
0x6a06380: ceNonLocalReturnTrampoline
0x6a063d8: ceCheckForInterruptsTrampoline
0x6a06430: ceFetchContextInstVarTrampoline
0x6a064a0: ceStoreContextInstVarTrampoline
0x6a06510: ceCannotResumeTrampoline
0x6a06570: ceBaseFrameReturnTrampoline
0x6a065c8: ceReturnToInterpreterTrampoline
0x6a06620: ceMallocTrampoline
0x6a06688: ceFreeTrampoline
```



##### Enilopmarts (reverse trampolines)

```smalltalk
generateEnilopmarts
	"Enilopmarts transfer control from C into machine code (backwards trampolines).
	 Override to add version for generic and PIC-specific entry with reg args."
	super generateEnilopmarts.

	self cppIf: Debug
		ifTrue:
			[realCECallCogCodePopReceiverArg0Regs :=
				self genEnilopmartFor: ReceiverResultReg
					and: Arg0Reg
					forCall: true
					called: 'realCECallCogCodePopReceiverArg0Regs'.
			 ceCallCogCodePopReceiverArg0Regs := #callCogCodePopReceiverArg0Regs.
			 realCECallCogCodePopReceiverArg1Arg0Regs :=
				self genEnilopmartFor: ReceiverResultReg
					and: Arg0Reg
					and: Arg1Reg
					forCall: true
					called: 'realCECallCogCodePopReceiverArg1Arg0Regs'.
			 ceCallCogCodePopReceiverArg1Arg0Regs := #callCogCodePopReceiverArg1Arg0Regs]
		ifFalse:
			[ceCallCogCodePopReceiverArg0Regs :=
				self genEnilopmartFor: ReceiverResultReg
					and: Arg0Reg
					forCall: true
					called: 'ceCallCogCodePopReceiverArg0Regs'.
			 ceCallCogCodePopReceiverArg1Arg0Regs :=
				self genEnilopmartFor: ReceiverResultReg
					and: Arg0Reg
					and: Arg1Reg
					forCall: true
					called: 'ceCallCogCodePopReceiverArg1Arg0Regs'].

	"These are special versions of the ceCallCogCodePopReceiverAndClassRegs enilopmart that also
	 pop register args from the stack to undo the pushing of register args in the abort/miss trampolines."
	ceCall0ArgsPIC := self genCallPICEnilopmartNumArgs: 0.
	self numRegArgs >= 1 ifTrue:
		[ceCall1ArgsPIC := self genCallPICEnilopmartNumArgs: 1.
		 self numRegArgs >= 2 ifTrue:
			[ceCall2ArgsPIC := self genCallPICEnilopmartNumArgs: 2.
			 self assert: self numRegArgs = 2]]
```

```bash
0x6a066f0: ceEnterCogCodePopReceiverReg
0x6a06720: ceCallCogCodePopReceiverReg
0x6a06758: ceCallCogCodePopReceiverAndClassRegs
0x6a06798: cePrimReturnEnterCogCode
0x6a06838: cePrimReturnEnterCogCodeProfiling
0x6a06928: ceCallCogCodePopReceiverArg0Regs
0x6a06968: ceCallCogCodePopReceiverArg1Arg0Regs
0x6a069b0: ceCallPIC0Args
0x6a069f0: ceCallPIC1Args
0x6a06a38: ceCallPIC2Args

```

#### Tracing trampolines

```smalltalk
generateTracingTrampolines
	"Generate trampolines for tracing.  In the simulator we can save a lot of time
	 and avoid noise instructions in the lastNInstructions log by short-cutting these
	 trampolines, but we need them in the real vm."
	ceTraceLinkedSendTrampoline :=
		self genTrampolineFor: #ceTraceLinkedSend:
			called: 'ceTraceLinkedSendTrampoline'
			arg: ReceiverResultReg
			regsToSave: CallerSavedRegisterMask.
	ceTraceBlockActivationTrampoline :=
		self genTrampolineFor: #ceTraceBlockActivation
			called: 'ceTraceBlockActivationTrampoline'
			regsToSave: CallerSavedRegisterMask..
	ceTraceStoreTrampoline :=
		self genTrampolineFor: #ceTraceStoreOf:into:
			called: 'ceTraceStoreTrampoline'
			arg: ClassReg
			arg: ReceiverResultReg
			regsToSave: CallerSavedRegisterMask..
	self cCode: [] inSmalltalk:
		[ceTraceLinkedSendTrampoline := self simulatedTrampolineFor: #ceShortCutTraceLinkedSend:.
		 ceTraceBlockActivationTrampoline := self simulatedTrampolineFor: #ceShortCutTraceBlockActivation:.
		 ceTraceStoreTrampoline := self simulatedTrampolineFor: #ceShortCutTraceStore:]
```



```bash
0x6a06a88: ceTraceLinkedSendTrampoline
0x6a06b10: ceTraceBlockActivationTrampoline
0x6a06b90: ceTraceStoreTrampoline
```
