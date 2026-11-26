# SPDX-FileCopyrightText: © 2024 Steven Xie
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

CLK_NS = 20 # in ns, prolly should work

#OPCODES

OUT, ADD, SUB, ADDI, STORE, LOAD, SHL, SHR, LDI, XOR, MOV, COMP, AND, JZ, JNZ, HALT_OP = range(16)