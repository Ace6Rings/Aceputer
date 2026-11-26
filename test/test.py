# SPDX-FileCopyrightText: © 2024 Steven Xie
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

CLK_NS = 20 # in ns, prolly should work

#OPCODES

OUT, ADD, SUB, ADDI, STORE, LOAD, SHL, SHR, LDI, XOR, MOV, COMP, AND, JZ, JNZ, HALT_OP = range(16)

#shift the bits to match how the cpu does stuff
# rr is just the arithmetic instructions. imm is immediate, branch is jump, halt is halt
rr = lambda op, rd=0, rs1=0, rs2=0: (op << 12) | ((rd & 7) << 9) | ((rs1 & 7) << 6 | ((rs2 & 7)<< 3)) 

imm = lambda op, rd, val: (op << 12) | ((rd & 7) << 9) | ((val & 0xFF) << 1)

branch = lambda op, rd, tgt: (op << 12) | ((rd & 7) << 9) | ((tgt & 0x7F) << 2)

HALT = HALT_OP << 12


