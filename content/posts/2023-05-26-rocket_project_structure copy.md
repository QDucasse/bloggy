---
title: "Rocket chip structure"
date: "2023-05-26"
tags: [
    "riscv",
    "rocket"
]
categories: [
    "Exploration"
]
---

## Rocket core structure and exploration

The objective here is to get a feeling of how things are defined in the [rocket chip generator](https://github.com/chipsalliance/rocket-chip). I will look at the files in [`src/main/scala/rocket`](https://github.com/chipsalliance/rocket-chip/tree/master/src/main/scala/rocket) for the latest release 1.6:

**Logic**:
- `ALU.scala`: Arithmetic logical unit - performs all base operations.
- `AMOALU.scala`: Atomic memory operation ALU - performs all atomic memory operations. 
- `Breakpoint.scala`: Breakpoint utilities
- `BTB.scala`: Branch target buffer - predicts branch targets
- `Decode.scala`: Decoder - applies the bit patterns defined in `IDecode`
- `Events.scala`: Events - assess performance or trace using a given mask
- `Frontend.scala`: Used by the C++ emulator
- `IBuf.scala`: Instruction buffer - 
- `ICache.scala`: (L1?) Instruction cache - program store
- `IDecode.scala`: Instruction decoder - links bit patterns from instructions to infos
- `Multiplier.scala`: Multiplication and division unit
- `RocketCore.scala`: Rocket definition - all internal signals and module instantiations
- `RVC.scala`: RVC decoder - RV compressed instructions handling


**Memory**:
- `DCache.scala`: (L1?) data cache
- `NBDcache.scala`: Non-blocking (L1?) data cache
- `HellaCacheArbiter.scala`: Arbiter for data cache - controls requests from the core, RoCC, FPU or PTW
- `HellaCache.scala`: L1 Cache - defines cache parameters and traits
- `SimpleHellaCacheIF.scala`:
- `TLB.scala`: Translation lookaside buffer
- `TLBPermissions.scala`:
- `PMP.scala`: Physical memory protection - defines the CSRs and checker
- `PTW.scala`: Page table walker
- `ScratchpadSlavePort.scala`: IO conversion - adapts between diplomacy (`TileLink`) and non-diplomacy (`HellaCacheIO`)

**Constants**:
- `Consts.scala`: Main constants used throughout the core definition
- `CSR.scala`: Control and status registers
- `CustomInstructions.scala`: Custom(0-3) instructions encoding and CSRs
- `Instructions32.scala`: RV32 specific instructions Encoding
- `Instructions.scala`: Instructions encodings, causes, and CSRs


## Diving in the `RocketCore`

The [`RocketCore.scala`](https://github.com/chipsalliance/rocket-chip/tree/master/src/main/scala/rocket/RocketCore.scala) file defines the inner pipeline of the Rocket CPU along with its IOs. It defines the main class, `Rocket`, and its parameters:

> *Note:* All core IOs are grouped after the pipeline and should be looked into to see the impact of a stage on the IOs!

1. **Performance Events:** The first definitions are performance events to record the usage of given instructions, cache information, and branch prediction accuracy. 

```scala
 new EventSet((mask, hits) => Mux(wb_xcpt, mask(0), wb_valid && pipelineIDToWB((mask & hits).orR)), Seq(
      /* Instructions */
      ("exception", () => false.B),
      ("load", () => id_ctrl.mem && id_ctrl.mem_cmd === M_XRD && !id_ctrl.fp),
      ("store", () => id_ctrl.mem && id_ctrl.mem_cmd === M_XWR && !id_ctrl.fp),
      ("system", () => id_ctrl.csr =/= CSR.N),
      ("branch", () => id_ctrl.branch),
      ...
      /* Interlocks and branches */
      ...
      ("long-latency interlock", () => id_sboard_hazard),
      ("I$ blocked", () => icache_blocked),
      ("D$ blocked", () => id_ctrl.mem && dcache_blocked),
      ("branch misprediction", () => take_pc_mem && mem_direction_misprediction),
      ("flush", () => wb_reg_flush_pipe),
      ("replay", () => replay_wb))
      ...
      /* Cache misses */
      ("I$ miss", () => io.imem.perf.acquire),
      ("D$ miss", () => io.dmem.perf.acquire),
      ("D$ release", () => io.dmem.perf.release),
      ("ITLB miss", () => io.imem.perf.tlbMiss),
      ("DTLB miss", () => io.dmem.perf.tlbMiss),
      ("L2 TLB miss", () => io.ptw.perf.l2miss))
```


2. **Decode Modules:** The decode modules are set up by adding them all to a common `decode_table` flattening their dictionaries.

```scala
  val decode_table = {
    require(!usingRoCC || !rocketParams.useSCIE)
    ...
    (usingRoCC.option(new RoCCDecode)) ++:
    (rocketParams.useSCIE.option(new SCIEDecode)) ++:
    (if (xLen == 32) new I32Decode else new I64Decode) +:
    ...
    Seq(new FenceIDecode(tile.dcache.flushOnFenceI)) ++:
    coreParams.haveCFlush.option(new CFlushDecode(tile.dcache.canSupportCFlushLine)) ++:
    Seq(new IDecode)
  } flatMap(_.table)
```


3. **Signal definitions:** All the signals used throughout the core are defined here with a prefix corresponding to their pipeline stage: `id` for *instruction decode*, `ex` for *execute*, `mem` for *memory*, and `wb` for *writeback*.

4. **Decode stage:** The decode stage instantiates an `IBuf` (Instruction Buffer) and runs the raw instruction against its decoders. An instruction is defined as a bit pattern of important bits and don't-cares, effectively defining a bit mask:

```scala
// in Instructions.scala
def ADD     = BitPat("b0000000??????????000?????0110011")
def ADD_UW  = BitPat("b0000100??????????000?????0111011")
def ADDI    = BitPat("b?????????????????000?????0010011")
```

These bit patterns are used as keys in the decoder, matching them with control signals, `IntCtrlSigs`:

```scala
// in IDecode.scala
class IntCtrlSigs extends Bundle {
  ...
  def default: List[BitPat] =
//           jal                                                             renf1               fence.i
//   val     | jalr                                                          | renf2             |
//   | fp_val| | renx2                                                       | | renf3           |
//   | | rocc| | | renx1       s_alu1                          mem_val       | | | wfd           |
//   | | | br| | | |   s_alu2  |       imm    dw     alu       | mem_cmd     | | | | mul         |
//   | | | | | | | |   |       |       |      |      |         | |           | | | | | div       | fence
//   | | | | | | | |   |       |       |      |      |         | |           | | | | | | wxd     | | amo
//   | | | | | | | | scie      |       |      |      |         | |           | | | | | | |       | | | dp
List(N,X,X,X,X,X,X,X,X,A2_X,   A1_X,   IMM_X, DW_X,  FN_X,     N,M_X,        X,X,X,X,X,X,X,CSR.X,X,X,X,X)
}

class IDecode(implicit val p: Parameters) extends DecodeConstants
{
  val table: Array[(BitPat, List[BitPat])] = Array(
    BNE->       List(Y,N,N,Y,N,N,Y,Y,N,A2_RS2,A1_RS1, 
                     IMM_SB,  DW_X,FN_SNE,  N,M_X,        
                     N,N,N,N,N,N,N,CSR.N,N,N,N,N),
    BEQ->       List(Y,N,N,Y,N,N,Y,Y,N,A2_RS2,A1_RS1,
                     IMM_SB,  DW_X,FN_SEQ,   N,M_X,        
                     N,N,N,N,N,N,N,CSR.N,N,N,N,N),
    ...
    )    
}
```
This `id_ctrl` signal contains high-level information for each instruction such as if it needs memory access, which ALU function to trigger, etc.

5. **Execute stage:** The execute stage instantiates an ALU and passes the decoded parameters. It can also run a multiplication/division through its dedicated unit:

```scala
val alu = Module(new ALU)
alu.io.dw := ex_ctrl.alu_dw
alu.io.fn := ex_ctrl.alu_fn
alu.io.in2 := ex_op2.asUInt
alu.io.in1 := ex_op1.asUInt

// multiplier and divider
val div = Module(new MulDiv(if (pipelinedMul) mulDivParams.copy(mulUnroll = 0) else mulDivParams, width = xLen))
div.io.req.valid := ex_reg_valid && ex_ctrl.div
div.io.req.bits.dw := ex_ctrl.alu_dw
div.io.req.bits.fn := ex_ctrl.alu_fn
div.io.req.bits.in1 := ex_rs(0)
div.io.req.bits.in2 := ex_rs(1)
div.io.req.bits.tag := ex_waddr
val mul = pipelinedMul.option {
val m = Module(new PipelinedMultiplier(xLen, 2))
m.io.req.valid := ex_reg_valid && ex_ctrl.mul
m.io.req.bits := div.io.req.bits
m
}
```

6. **Memory stage:** The memory stage extracts the branch targets, and transfers the control signals to the next stage. The signals are used in the instruction memory through the Branch Target Buffer (BTB). Note that single-cycle latency instructions simply have their results forwarded to the next stage. This forwarding ensures that both one- and two-cycle instructions always write their results in the same stage of the pipeline so that just one write port to the register file can be used, and it is always available. 


7. **Writeback stage:** The writeback stage writes the result of the operations in the register file.

8. **IOs:** Other signals put at the end interact with the IOs of the core:

- CSR update
- Instruction memory update
- PTW update
- Data memory update

```scala
// Data memory request from the execute stage
  io.dmem.req.bits.tag  := ex_dcache_tag
  io.dmem.req.bits.cmd  := ex_ctrl.mem_cmd
  io.dmem.req.bits.size := ex_reg_mem_size 
  io.dmem.req.bits.signed := !Mux(ex_reg_hls, ex_reg_inst(20), ex_reg_inst(14))
```


## Integrating `Rocket` in a `RocketTile`

The IOs presented earlier are needed to define the Rocket core with its peripherals. The so-called *tiles* are defined in [`src/main/scala/tile`](https://github.com/chipsalliance/rocket-chip/tree/master/src/main/scala/tile). The [`RocketTile`](https://github.com/chipsalliance/rocket-chip/tree/master/src/main/scala/tile/RocketTile.scala), extending [`BaseTile`](https://github.com/chipsalliance/rocket-chip/tree/master/src/main/scala/tile/BaseTile.scala) presents the integration of the `Rocket` core along its peripherals:

```scala
class RocketTileModuleImp(outer: RocketTile) extends BaseTileModuleImp(outer)
    with HasFpuOpt
    with HasLazyRoCCModule
    with HasICacheFrontendModule {
  Annotated.params(this, outer.rocketParams)

  val core = Module(new Rocket(outer)(outer.p))
  ...
  (various error passing)
  ...

  // Connect the core pipeline to other intra-tile modules
  outer.frontend.module.io.cpu <> core.io.imem
  dcachePorts += core.io.dmem
  fpuOpt foreach { fpu => core.io.fpu <> fpu.io }
  core.io.ptw <> ptw.io.dpath
  
  // Connect the coprocessor interfaces
  if (outer.roccs.size > 0) {
    cmdRouter.get.io.in <> core.io.rocc.cmd
    outer.roccs.foreach(_.module.io.exception := core.io.rocc.exception)
    core.io.rocc.resp <> respArb.get.io.out
    core.io.rocc.busy <> (cmdRouter.get.io.busy || outer.roccs.map(_.module.io.busy).reduce(_ || _))
    core.io.rocc.interrupt := outer.roccs.map(_.module.io.interrupt).reduce(_ || _)
  }

  ...
}
```


## Looking at memory accesses and the PMP

Now that we have a better understanding of the project structure, pipeline, and peripherals that Rocket uses we can look more in detail at Rocket memory accesses, how they are formatted, how they are passed to the data memory, and how they are processed checked by the PMP.

1. **Load/Stores instructions:** In the RISC-V ISA, each instruction defines its `opcode` (bits 0-7) and might precise the `opcode` with `funct3`. In the case of loads and stores, the encoding is the following:

```
LOAD - x[rd] = M[x[rs1] + sext(offset)][WIDTH]
             = sext(M[x[rs1] + sext(offset)][WIDTH]) if SGN

| 31                  20|19    15|14       12|11           7|6        0 |
|       imm [11:0]      |  rs1   |  funct3   |      rd      |  opcode   |
|         OFFSET        |   _    | SGN|WIDTH |              |  STORE    |


STORE - M[x[rs1] + sext(offset)] = x[rs2][WIDTH] 

| 31          25|24    20|19    15|14       12|11          7|6        0 |
|    imm [11:5] |  rs2   |  rs1   |  funct3   |     rd      |  opcode   |
|     OFFSET1   |        _        | _ |WIDTH  | offset[4:0] |   LOAD    |
```

The opcode defines the type of instruction, `load`/`store`. While the registers are different in their usage, `load`s use an offset encoded over `rs2` while `store` use `rs2` as the source register holding the data to move to memory. The `funct3` field define the width of the access with its least significant bits (12 and 13) that corresponds to: `00` for a `byte`, `01` for a `half-word` (2 bytes), `10` for a `word` (4 bytes) and `11` for a `double` (8 bytes). The bit 14 is used to differenciate signed and unsigned loads.

> *Note:* unsigned store do not exist as they do not need to be sign-extended to field a register!
