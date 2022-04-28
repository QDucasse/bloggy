---
title: "Adding instructions to the RISC-V Rocket core"
date: "2022-04-12"
tags: [
    "riscv",
    "rocket"
]
categories: [
    "Exploration"
]
---

## Introduction

The RISC-V ISA was born with modularity, extensibility, and open-source in mind. To this end, several processors have their source code available and can be modified to add co-processing units or even new instructions. Our objective here will be to add duplicated instructions in the Rocket core to implement the backbone of a security model presented in RIMI.

## Choosing the opcodes

We need to duplicate several instructions:

- `lbu`, `lhu`, `lwu` and `ld` for `loads`
- `sb`, `sh`, `sw` and `sd` for `stores`
- `jal` and `jalr` to add a *domain change* possibility

The repository `riscv-opcodes` contains all instruction opcodes:

```
LBU:
31              20 19     15 14    12 11     7 6          0
|  	offset[11:0]  |   rs1   |  100   |   rd   |  0000011  |

LHU:
31              20 19     15 14    12 11     7 6          0
|  	offset[11:0]  |   rs1   |  101   |   rd   |  0000011  |

LWU:
31              20 19     15 14    12 11     7 6          0
|  	offset[11:0]  |   rs1   |  110   |   rd   |  0000011  |

LD:
31              20 19     15 14    12 11     7 6          0
|  	offset[11:0]  |   rs1   |  011   |   rd   |  0000011  |

SB:
31              25 24     20 19     15 14    12 11            7 6          0
|  	offset[11:5]  |   rs2   |   rs1   |  000   |  offset[4:0]  |  0100011  |

SH:
31              25 24     20 19     15 14    12 11            7 6          0
|  	offset[11:5]  |   rs2   |   rs1   |  001   |  offset[4:0]  |  0100011  |

SW:
31              25 24     20 19     15 14    12 11            7 6          0
|  	offset[11:5]  |   rs2   |   rs1   |  010   |  offset[4:0]  |  0100011  |

SD:
31              25 24     20 19     15 14    12 11            7 6          0
|  	offset[11:5]  |   rs2   |   rs1   |  011   |   offset[4:0] |  0100011  |
```



Instructions are structured in a way where two opcodes can be differentiated: first, the seven bits (0 to 6) then the three bits (12 to 14) that we will call `op7` and `op3` respectively. `op3` is useful to specify the length of the global instruction. For example in our cases, the variations from byte to double.
