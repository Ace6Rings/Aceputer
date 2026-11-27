# SPDX-FileCopyrightText: © 2024 Steven Xie
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

CLK_NS = 100

# OPCODES
OUT, ADD, SUB, ADDI, STORE, LOAD, SHL, SHR, LDI, XOR, MOV, COMP, AND, JZ, JNZ, HALT_OP = range(16)

rr = lambda op, rd=0, rs1=0, rs2=0: (op << 12) | ((rd & 7) << 9) | ((rs1 & 7) << 6) | ((rs2 & 7) << 3)
imm = lambda op, rd, val: (op << 12) | ((rd & 7) << 9) | ((val & 0xFF) << 1)
branch = lambda op, rd, tgt: (op << 12) | ((rd & 7) << 9) | ((tgt & 0x7F) << 2)
HALT = HALT_OP << 12

CS_HIGH = 0x10  # ui_in[4] = 1 (idle)

def qspi_miso(dut):
    return int(dut.uo_out.value) & 0xF

def qspi_halted(dut):
    return (int(dut.uo_out.value) >> 4) & 1

def qspi_req_out(dut):
    return (int(dut.uo_out.value) >> 5) & 1

async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    dut.ena.value = 1
    dut.uio_in.value = 0
    dut.ui_in.value = CS_HIGH
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

async def send_word(dut, word):
    # Shift 4 nibbles MSB-first with CS=0, then raise CS=1 while SRAM writes
    for shift in (12, 8, 4, 0):
        dut.ui_in.value = (word >> shift) & 0xF
        await RisingEdge(dut.clk)
    dut.ui_in.value = CS_HIGH
    await ClockCycles(dut.clk, 5)

async def run_program(dut, program, n_outputs):
    await reset(dut)
    seen = []

    for word in program:
        await send_word(dut, word)

    for _ in range(30 * len(program) + 1000):
        await RisingEdge(dut.clk)
        if qspi_req_out(dut):
            # Drop CS=0 and capture the last 4 nibbles before qspi_req_out clears
            dut.ui_in.value = 0x00
            val = 0
            while qspi_req_out(dut):
                val = ((val << 4) | qspi_miso(dut)) & 0xFFFF
                await RisingEdge(dut.clk)
            dut.ui_in.value = CS_HIGH
            seen.append(val)

            if len(seen) == n_outputs:
                await ClockCycles(dut.clk, 40)
                assert qspi_halted(dut) == 1
                assert qspi_req_out(dut) == 0
                return seen

    assert False

@cocotb.test()
async def test_reset_idle(dut):
    await reset(dut)
    await ClockCycles(dut.clk, 20)
    assert int(dut.uio_oe.value) == 0x00 and int(dut.uo_out.value) == 0x00

@cocotb.test()
async def test_isa_and_memory(dut):
    prog = [
        imm(LDI, 1, 0xFF),
        imm(LDI, 2, 0x03),
        rr(ADD, 3, 1, 2),
        rr(SUB, 4, 2, 1),
        rr(OUT, 0, 3, 4),
        imm(ADDI, 2, 0xFF),
        rr(MOV, 5, 1),
        rr(AND, 5, 5, 2),
        rr(XOR, 5, 5, 1),
        rr(COMP, 6, 1, 1),
        rr(OUT, 0, 5, 6),
        imm(LDI, 3, 0x81),
        rr(SHL, 3),
        rr(SHR, 3),
        rr(OUT, 0, 3, 7),
        rr(SHR, 3),
        imm(STORE, 5, 0xF0),
        imm(LOAD, 4, 0xF0),
        imm(LDI, 0, 0x42),
        rr(ADD, 0, 1, 2),
        rr(ADD, 4, 4, 0),
        rr(OUT, 0, 4, 3),
        HALT,
    ]
    assert await run_program(dut, prog, 4) == [0x0204, 0xFD01, 0x0100, 0xFD00]

@cocotb.test()
async def test_branches_and_halt(dut):
    prog = [
        imm(LDI, 1, 0),
        imm(LDI, 2, 3),
        branch(JZ, 1, 4),
        imm(LDI, 2, 99),
        branch(JZ, 2, 8),
        rr(OUT, 0, 2, 1),
        imm(ADDI, 2, 0xFF),
        branch(JNZ, 2, 5),
        HALT,
        imm(LDI, 1, 0xEE),
        rr(OUT, 0, 1, 1),
    ]
    assert await run_program(dut, prog, 3) == [0x0300, 0x0200, 0x0100]

@cocotb.test()
async def test_max_program(dut):
    prog = [imm(LDI, 1, 0xAB)] * 126 + [rr(OUT, 0, 1, 1)]
    assert await run_program(dut, prog, 1) == [0xABAB]