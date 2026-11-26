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

#read uio and uo, and concatenate them
def bus(dut):
    return (int(dut.uio_out.value) << 8) | int(dut.uo_out.value)

#start
async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())

#reset cpu and clear registers
dut.ena.value = 1
dut.uio_in.value = 0
dut.rst_n.value = 0

await ClockCycles(dut.clk, 5) # wait for 5 clock cycles
dut.rst_n.value = 1

async def run_program(dut, program, n_outputs):
    await reset(dut) #resets

for word in program:
    dut.ui_in.value = word & 0xFF
    dut.uio_in.value == (word >> 8) & 0xFF
    await ClockCycles(dut.clk, 3) #maybe do 2? if 3 doesn't work, do 2

seen = []
    for in_range(20 * len(program) + 1000) #set it to some random ass number

await RisingEdge(dut.clk)
    if int(dut.uio_oe.value) == 0xFF #check if state is HALT 

val = bus(dut)
     if val != (seen[-1] if seen else None):
    seen.append(val) #prevents reading the same output. prolly unneeded?

if len(seen) == n_outputs:
    await ClockCycles(dut.clk, 40)
    assert int(dut.uio_oe.value) == 0xFF
    assert bus(dut) == val
    return seen
assert False #assert false if for loop doesnt return seen

@cocotb.test()
async def test_reset_idle(dut)
    await reset (dut)
    await ClockCyles(dut.clk, 20)
    await int(dut.uio_oe.value) == 0x00 and bus(dut) == 0x0000 #resets cpu and see if uio_oe stays at 0x00 and outputs stay 0x0000

@cocotb.test()
async def test_isa_and_memory(dut):
    prog = [
        imm(LDI, 1, 0xFF), # r1 is set to 255
        imm(LDI, 2, 0x03), # to 3
        rr(ADD, 3, 1, 2),  #overflow
        rr(SUB, 4, 2, 1),  #underflow, check this and see if ts is right 
        rr(OUT, 0, 3, 4),  #should output some stuff
        imm(ADDI, 2, 0xFF), #











    ]


                     
