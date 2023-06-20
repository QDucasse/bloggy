---
title: "Rocket chip structure"
date: "2023-06-19"
tags: [
    "riscv",
    "rocket"
]
categories: [
    "Exploration"
]
---

## Address checking in Rocket

### General address resolution

**Virtual Memory:** (*Chapter from [[1]](https://safari.ethz.ch/projects_and_seminars/spring2022/lib/exe/fetch.php?media=pns_hwsw2022_lecture3_vm.pdf)*) In a CPU, pages of virtual memory are used by programs running on a computer. Virtual addresses are linked to corresponding physical addresses on the base of memory pages. A *page table* stored in memory (RAM) contains the links between virtual and physical addresses. This page table is unique for each running program on a computer through the program's address space. The **Memory Management Unit (MMU)** is responsible for resolving address translation requests (one/core usually!). It typically contains:

- **Translation Lookaside Buffers (TLBs)** that cache recently used virtual-to-physical translations (Page Table Entries or PTEs)
- **Page Table Walk Caches** that offer fast access to the intermediate levels of large and multi-level page tables
- **Hardware Page Table Walker (PTW)** that sequentially accesses the different levels of the page table to fetch the required PTE.

> *Note:* In the case of a TLB miss, either the hardware performs the page walk and inserts the new entry in the TLB (*e.g.* x86 or the Rocket CPU!) or the operating system does the page walk and inserts the entry in the TLB (*e.g.* MIPS).

**RISC-V Virtual Memory:** RISC-V supports different virtual memory systems depending on the size of the address space, *e.g.* RV64 Sv39 supports 4KB base pages as well as 2MB and 1GB superpages. The page table is implemented as a multi-level radix tree (3-level page table in RV64 Sv39).

### Physical Memory Protection unit

Physical Memory Protection (PMP) is a memory protection mechanism that allows **M-mode** to create and assign permissions to **contiguous** physical memory regions. The PMP is configured by M-mode through two sets of registers:
- `pmpaddr0` - `pmpaddr15`: specify the physical addresses of PMP regions
- `pmpcfg0` - `pmpcfg1`: contain the configurations (8-bits wide) for each PMP region

Each **configuration** is packed in **configuration registers** (4 configs in one register) and follows the 8-bit wide format `L|00|A|X|W|R` with the fields representing:
- `R.1`: Read permission
- `W.1`: Write permission
- `X.1`: Execution permission
- `A.2`: Address matching type can be one of
    - 0: `OFF`, no PMP checks
    - 1: `TOR`, top of range
    - 2: `NA4`, naturally aligned four-byte region
    - 3: `NAPOT`, naturally aligned power-of-two region (bigger than 8 bytes)
- `L.1`: Lock flag, indicating that writes to the configuration and associated address registers are ignored.

Each **address register** contains the address (wow!) as `address[33:2]` for RV32 and `0000000000|address[55:2]` for RV64.

> *Note:* Each field in `pmpcfgi` and `pmpaddri` follows the **`WARL`** behavior defined in the specification. The following behaviors are defined: 
> - *Write Preserve Read Ignore (WPRI)*: read/write fields are reserved fo future use, software should ignore the values read from these fields and preserve the values in them when writing to other fields in the same registers.
> - *Write Legal Read Legal (WLRL)*: software should only write legal values to a field and should not assume that a read will return a legal value unless 
> - *Write Any Read Legal (WARL)*: the field is only defined for a subset of bit encodings but any value can be written to the and a legal value is guaranteed to be read.

### Rocket components

**Rocket MMU:** The Rocket Memory Management Unit (MMU) [[3]](https://www.researchgate.net/figure/Overview-of-the-MMU-in-Rocket-Chip-Generator_fig1_344276865) consists of L1 Instruction/Data TLB that are nearly identical (except for minor differences regarding access privileges to pages). The L2 TLB is shared among L1 I/DTLBs and can contain both instruction and data page translations. The Page Table Walker (PTW) incorporates the shared L2 TLB. It is connected with the L1 I/DTLBs through a round-robin arbiter that selects the target virtual address to be translated. The PTW uses a cache to store the non-leaf virtual-to-physical page translations.

![](/images/rocket_mmu_overview.png)

Some qualifications on the different caches:
- **L1 I/DTLB**: Vector of Chisel `Reg` elements, positive-edge-triggered registers. Fully associative with a configurable number of entries and a Pseudo-LRU replacement policy. It responds with a hit/miss indication on the next cycle. It stores translations of pages and super pages.

- **L2 TLB**: Chisel's `SyncReadMem/SeqMem` construct, which can be synthesized to FPGA Block RAM or ASIC SRAM. It creates a synchronous-read, synchronous-write memory with one read and one write port. It outputs to a register and holds intermediate stages until it informs of a hit/miss.

- **PTW Cache**: Small fully-associative cache that stores the non-leaf virtual-to-physical pages.


**Rocket PMP:** Cheang et al. [[2]](https://arxiv.org/abs/2211.02179) formally verify the correctness of the `PMPChecker` methods itself. While their wider goal is to formally verify the [Keystone](https://keystone-enclave.org/) enclave framework, they present this first step on the main PMP verification. They show the PMP rules are "functionally correct" but miss the interaction with TLB and PTW (and correct software implementation as well). Memory access may bypass the PMP rule if the address is cached in the TLB. To prevent this, most systems flush the TLB whenever it changes the local PMP policy.


### References

[[1]](https://safari.ethz.ch/projects_and_seminars/spring2022/lib/exe/fetch.php?media=pns_hwsw2022_lecture3_vm.pdf) P&S HW/SW Co-design, Lecture 3: Virtual Memory (II) by Konstantinos Kanellopoulos from ETH Zurich

[[2]](https://arxiv.org/abs/2211.02179) Verifying RISC-V Physical Memory Protection,
Kevin Cheang et al.

[[3]](https://www.researchgate.net/figure/Overview-of-the-MMU-in-Rocket-Chip-Generator_fig1_344276865) Enabling Virtual Memory Research on RISC-V with a Configurable TLB Hierarchy for the Rocket Chip Generator, Charalampos et al.