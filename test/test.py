# SPDX-FileCopyrightText: © 2024 Steven Xie
# SPDX-License-Identifier: Apache-2.0
"""cocotb test suite for the Aceputer - a 16 bit CPU with an 8 bit datapath.

How the chip is used
--------------------
* `ui_in`   = low byte  of the 16 bit instruction word / output bus
* `uio_in`  = high byte of the 16 bit instruction word (input mode)
* `uio_oe`  = 0 while the CPU is loading a program (the host drives `uio_in`),
              becomes 0xFF as soon as the CPU drives the output bus
* `uo_out` / `uio_out` = low / high byte of the last `OUT` instruction

Programming: reset the chip, put instruction word 0 on `{uio_in, ui_in}` and
hold it stable for three clocks; repeat for every word.  The program is stored
as two bytes per word (byte 0 = low byte of the instruction) starting at
address 0, so instruction *i* lives at bytes 2i and 2i+1.  As soon as an
instruction with opcode `HALT` is written, the loader stops, forces `pc` to 0
and starts executing.  Writing 128 words without a `HALT` forces one at the
last slot (word 127).

The instruction encoding is::

    [15:12] opcode
    [11:9]  rd
    [8:6]   rs1
    [5:3]   rs2
    [8:1]   imm8   (LDI, ADDI, STORE address, LOAD address)
    [8:2]   target (JZ / JNZ)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

# 10 MHz - slow enough to also work for gate level simulation with SDF delays
CLK_PERIOD_NS = 100

# The CPU samples one instruction word every three clock cycles while in
# PROGRAM state, so every word has to be held for exactly three clocks.
LOAD_HOLD_CYCLES = 3

MAX_PROGRAM_WORDS = 127  # word 127 is reserved for the forced HALT

# FSM state encoding from project.v (internal, only visible in RTL simulation)
STATE_HALT = 0b010


# ---------------------------------------------------------------------------
# Tiny assembler
# ---------------------------------------------------------------------------
OP_OUT, OP_ADD, OP_SUB, OP_ADDI, OP_STORE, OP_LOAD, OP_SHL, OP_SHR, \
    OP_LDI, OP_XOR, OP_MOV, OP_COMP, OP_AND, OP_JZ, OP_JNZ, OP_HALT = range(16)


def rr(op, rd=0, rs1=0, rs2=0):
    """Register-register instruction."""
    return (op << 12) | ((rd & 0x7) << 9) | ((rs1 & 0x7) << 6) | ((rs2 & 0x7) << 3)


def imm(op, rd, value):
    """Register-immediate instruction (imm8 sits in instruction[8:1])."""
    return (op << 12) | ((rd & 0x7) << 9) | ((value & 0xFF) << 1)


def branch(op, rd, target):
    """JZ / JNZ - 7 bit word address in instruction[8:2]."""
    return (op << 12) | ((rd & 0x7) << 9) | ((target & 0x7F) << 2)


def ldi(rd, value):   return imm(OP_LDI, rd, value)
def addi(rd, value):  return imm(OP_ADDI, rd, value)
def add(rd, s1, s2):  return rr(OP_ADD, rd, s1, s2)
def sub(rd, s1, s2):  return rr(OP_SUB, rd, s1, s2)
def and_(rd, s1, s2): return rr(OP_AND, rd, s1, s2)
def xor(rd, s1, s2):  return rr(OP_XOR, rd, s1, s2)
def comp(rd, s1, s2): return rr(OP_COMP, rd, s1, s2)
def mov(rd, s1):      return rr(OP_MOV, rd, s1)
def shl(rd):          return rr(OP_SHL, rd)
def shr(rd):          return rr(OP_SHR, rd)
def out(s1, s2):      return rr(OP_OUT, 0, s1, s2)
def store(rd, addr):  return imm(OP_STORE, rd, addr)
def load(rd, addr):   return imm(OP_LOAD, rd, addr)
def jz(rd, target):   return branch(OP_JZ, rd, target)
def jnz(rd, target):  return branch(OP_JNZ, rd, target)
HALT = OP_HALT << 12


# ---------------------------------------------------------------------------
# Testbench driver
# ---------------------------------------------------------------------------
class Aceputer:
    """Drives the pins of the DUT and records what the CPU prints via OUT."""

    def __init__(self, dut):
        self.dut = dut
        self.log = dut._log

    # -- helpers ----------------------------------------------------------
    def bus(self):
        """Value currently on the 16 bit output bus ({uio_out, uo_out})."""
        return (int(self.dut.uio_out.value) << 8) | int(self.dut.uo_out.value)

    # -- start / reset ----------------------------------------------------
    async def start(self):
        cocotb.start_soon(Clock(self.dut.clk, CLK_PERIOD_NS, unit="ns").start())
        self.dut.ena.value = 1
        self.dut.ui_in.value = 0
        self.dut.uio_in.value = 0
        self.dut.rst_n.value = 0
        await ClockCycles(self.dut.clk, 10)

    async def reset(self):
        """Full reset: returns to PROGRAM with an empty write pointer.

        The last thing this does is release `rst_n` *without* waiting for a
        clock edge - the CPU samples the first instruction word at the very
        next rising edge, so the caller has to have it on the pins before then
        (`load()` does that).
        """
        self.dut.rst_n.value = 0
        self.dut.ui_in.value = 0
        self.dut.uio_in.value = 0
        await ClockCycles(self.dut.clk, 5)
        self.dut.rst_n.value = 1

    # -- program loading --------------------------------------------------
    async def load(self, program):
        """Shift a program into instruction memory (one word per 3 clocks)."""
        if len(program) > MAX_PROGRAM_WORDS:
            raise ValueError(
                f"program has {len(program)} words, the CPU only executes "
                f"{MAX_PROGRAM_WORDS} (word {MAX_PROGRAM_WORDS} is forced to HALT)"
            )
        for word in program:
            # Present the word before the edge that samples it.  Word 0 is
            # sampled at the first clock after reset is released, which is
            # exactly where `reset()` handed control back to us.
            self.dut.ui_in.value = word & 0xFF          # low byte  -> ui_in
            self.dut.uio_in.value = (word >> 8) & 0xFF   # high byte -> uio_in
            await ClockCycles(self.dut.clk, LOAD_HOLD_CYCLES)

    # -- execution --------------------------------------------------------
    async def run(self, n_outputs, max_cycles=None):
        """Wait until `n_outputs` OUT instructions have been printed.

        Returns the list of 16 bit values seen on {uio_out, uo_out}, in order.

        The CPU only drives the output pins while `uio_oe` is 0xFF, so a new
        output is "the output pins are being driven and the value on them
        changed".  Note that `uio_oe` stays high across back-to-back `OUT`
        instructions, and that two consecutive `OUT`s of the *same* value are
        indistinguishable from the outside - test programs should print
        distinct values (as they do here).
        """
        if max_cycles is None:
            max_cycles = 2000
        seen = []
        for cycle in range(max_cycles):
            await RisingEdge(self.dut.clk)
            if int(self.dut.uio_oe.value) == 0:
                continue
            value = self.bus()
            if value != (seen[-1] if seen else None):
                seen.append(value)
                self.log.info("cycle %d: OUT 0x%04x", cycle, value)
                if len(seen) == n_outputs:
                    return seen
        raise AssertionError(
            f"only saw {len(seen)} of {n_outputs} OUT instructions within "
            f"{max_cycles} cycles (got {[hex(v) for v in seen]}) - the CPU "
            f"probably stalled or jumped to the wrong address"
        )

    async def run_program(self, program, n_outputs):
        await self.reset()
        await self.load(program)
        return await self.run(n_outputs, max_cycles=40 * len(program) + 400)

    # -- assertions -------------------------------------------------------
    def state(self):
        """Internal FSM state, or None if it is not visible (gate level sim)."""
        try:
            return int(self.dut.user_project.state.value)
        except (AttributeError, ValueError):
            return None

    async def wait_for_halt(self, max_cycles=400):
        """Wait for the FSM to park in HALT. None if not observable (GL sim)."""
        for _ in range(max_cycles):
            st = self.state()
            if st is None:
                await ClockCycles(self.dut.clk, max_cycles)
                return None
            if st == STATE_HALT:
                return True
            await RisingEdge(self.dut.clk)
        return False

    async def assert_halted(self, stable_cycles=20):
        """At HALT the CPU keeps driving the last OUT value and uio_oe = 0xFF."""
        reached = await self.wait_for_halt()
        assert reached is not False, "CPU never reached HALT"
        # the HALT branch drives `uio_oe` on the clock edge after the state
        # change, so give it a cycle before looking at the pins
        await ClockCycles(self.dut.clk, 2)

        assert int(self.dut.uio_oe.value) == 0xFF, "uio_oe must be all outputs at HALT"
        value = self.bus()
        await ClockCycles(self.dut.clk, stable_cycles)
        assert int(self.dut.uio_oe.value) == 0xFF, "uio_oe changed after HALT"
        assert self.bus() == value, (
            f"output bus changed after HALT: 0x{value:04x} -> 0x{self.bus():04x}"
        )
        return value


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
@cocotb.test()
async def test_reset_and_program_mode(dut):
    """After reset the CPU is in PROGRAM mode and does not drive the IO pins."""
    cpu = Aceputer(dut)
    await cpu.start()
    await cpu.reset()

    assert int(dut.uio_oe.value) == 0x00, "uio_oe must be 0 so the host can drive uio_in"
    assert cpu.bus() == 0x0000, "output bus must be 0 after reset"

    # idle for a while - nothing may happen while no program was loaded
    await ClockCycles(dut.clk, 30)
    assert int(dut.uio_oe.value) == 0x00, "uio_oe must stay 0 before the first OUT"
    assert cpu.bus() == 0x0000, "output bus must stay 0 before the first OUT"


@cocotb.test()
async def test_alu(dut):
    """LDI, ADD, SUB, MOV, AND, XOR, COMP and ADDI."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [
        ldi(1, 10),            # 0: r1 = 10
        ldi(2, 3),             # 1: r2 = 3
        add(3, 1, 2),          # 2: r3 = 13
        sub(4, 1, 2),          # 3: r4 = 7
        out(3, 4),             # 4: print {r3, r4} = 0x0d07
        mov(5, 3),             # 5: r5 = r3 = 13
        and_(6, 5, 1),         # 6: r6 = 13 & 10 = 8
        xor(6, 6, 2),          # 7: r6 = 8 ^ 3 = 11
        comp(7, 1, 2),         # 8: r7 = (10 == 3) = 0
        out(4, 7),             # 9: print {r4, r7} = 0x0700
        addi(1, 0xFF),         # 10: r1 = 10 + 255 = 9 (mod 256)
        out(1, 1),             # 11: print {r1, r1} = 0x0909
        HALT,                  # 12
    ]

    seen = await cpu.run_program(program, n_outputs=3)
    assert seen == [0x0D07, 0x0700, 0x0909], f"unexpected OUT sequence {[hex(v) for v in seen]}"
    await cpu.assert_halted()


@cocotb.test()
async def test_alu_wrap_around(dut):
    """8 bit add/sub wrap around; COMP reports equality."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [
        ldi(1, 0xFF),          # 0: r1 = 255
        ldi(2, 0x02),          # 1: r2 = 2
        add(3, 1, 2),          # 2: r3 = 1   (overflow)
        sub(4, 2, 1),          # 3: r4 = 3   (underflow)
        comp(5, 1, 1),         # 4: r5 = 1   (255 == 255)
        comp(6, 1, 2),         # 5: r6 = 0   (255 != 2)
        out(3, 4),             # 6: 0x0103
        out(5, 6),             # 7: 0x0100
        HALT,                  # 8
    ]

    seen = await cpu.run_program(program, n_outputs=2)
    assert seen == [0x0103, 0x0100], f"unexpected OUT sequence {[hex(v) for v in seen]}"
    await cpu.assert_halted()


@cocotb.test()
async def test_shifts(dut):
    """SHL / SHR shift the destination register by one, bits fall off the end."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [
        ldi(1, 0x81),          # 0: r1 = 0x81
        shl(1),                # 1: r1 = 0x02
        shr(1),                # 2: r1 = 0x01
        shl(1),                # 3: r1 = 0x02
        out(1, 1),             # 4: 0x0202
        ldi(2, 0x01),          # 5: r2 = 0x01
        shr(2),                # 6: r2 = 0x00
        out(2, 1),             # 7: 0x0002
        HALT,                  # 8
    ]

    seen = await cpu.run_program(program, n_outputs=2)
    assert seen == [0x0202, 0x0002], f"unexpected OUT sequence {[hex(v) for v in seen]}"
    await cpu.assert_halted()


@cocotb.test()
async def test_jnz_loop(dut):
    """JNZ counts down a register: the classic loop test."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [
        ldi(1, 5),             # 0: r1 = loop counter
        ldi(2, 0),             # 1: r2 = accumulator
        addi(2, 1),            # 2: loop: r2++
        addi(1, 0xFF),         # 3: r1-- (add 255 = subtract 1)
        jnz(1, 2),             # 4: repeat while r1 != 0
        out(2, 1),             # 5: 0x0500
        HALT,                  # 6
    ]

    seen = await cpu.run_program(program, n_outputs=1)
    assert seen == [0x0500], f"loop ran {seen[0] >> 8} times instead of 5"
    await cpu.assert_halted()


@cocotb.test()
async def test_jz_taken_and_not_taken(dut):
    """JZ skips an instruction when the register is zero, falls through otherwise."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [
        ldi(1, 0),             # 0: r1 = 0
        ldi(2, 0x42),          # 1: r2 = 0x42
        jz(1, 4),              # 2: taken -> jump over instruction 3
        ldi(2, 0xEE),          # 3: must be skipped
        out(2, 2),             # 4: 0x4242
        jz(2, 7),              # 5: not taken (r2 != 0)
        ldi(3, 0x01),          # 6: executed
        out(3, 2),             # 7: 0x0142
        HALT,                  # 8
    ]

    seen = await cpu.run_program(program, n_outputs=2)
    assert seen == [0x4242, 0x0142], f"unexpected OUT sequence {[hex(v) for v in seen]}"
    await cpu.assert_halted()


@cocotb.test()
async def test_load_store(dut):
    """STORE writes a register to SRAM, LOAD reads it back (data at 0xF0/0xF1)."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [
        ldi(1, 0x5A),          # 0
        store(1, 0xF0),        # 1: mem[0xF0] = 0x5A
        ldi(1, 0x00),          # 2: clobber r1
        load(1, 0xF0),         # 3: r1 = mem[0xF0]
        out(1, 1),             # 4: 0x5A5A
        ldi(2, 0xA5),          # 5
        store(2, 0xF1),        # 6: mem[0xF1] = 0xA5
        ldi(2, 0x00),          # 7
        load(3, 0xF1),         # 8: r3 = mem[0xF1]
        out(3, 2),             # 9: 0xA500
        HALT,                  # 10
    ]

    seen = await cpu.run_program(program, n_outputs=2)
    assert seen == [0x5A5A, 0xA500], f"unexpected OUT sequence {[hex(v) for v in seen]}"
    await cpu.assert_halted()


@cocotb.test()
async def test_back_to_back_memory_access(dut):
    """STORE immediately followed by LOAD (and LOAD followed by STORE) works."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [
        ldi(1, 0x33),          # 0
        store(1, 0xF2),        # 1: mem[0xF2] = 0x33
        load(2, 0xF2),         # 2: read it straight back
        store(2, 0xF3),        # 3: store it again, elsewhere
        load(3, 0xF3),         # 4
        out(2, 3),             # 5: 0x3333
        HALT,                  # 6
    ]

    seen = await cpu.run_program(program, n_outputs=1)
    assert seen == [0x3333], f"unexpected OUT value {hex(seen[0])}"
    await cpu.assert_halted()


@cocotb.test()
async def test_register_zero_is_read_only(dut):
    """r0 is hardwired to 0: writes to it are ignored."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [
        ldi(1, 0x7F),          # 0
        ldi(0, 0x11),          # 1: ignored
        mov(0, 1),             # 2: ignored
        add(0, 1, 1),          # 3: ignored
        out(0, 0),             # 4: 0x0000
        HALT,                  # 5
    ]

    seen = await cpu.run_program(program, n_outputs=1)
    assert seen == [0x0000], f"r0 was writable: {hex(seen[0])}"
    await cpu.assert_halted()


@cocotb.test()
async def test_halt_freezes_output_bus(dut):
    """After HALT the last OUT value stays on the pins and uio_oe stays 0xFF."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [
        ldi(1, 0x12),          # 0
        ldi(2, 0x34),          # 1
        out(1, 2),             # 2: 0x1234
        HALT,                  # 3
    ]

    seen = await cpu.run_program(program, n_outputs=1)
    assert seen == [0x1234], f"unexpected OUT value {hex(seen[0])}"

    # ... and it must stay there
    halted_value = await cpu.assert_halted(stable_cycles=50)
    assert halted_value == 0x1234, f"halted output is {hex(halted_value)}"


@cocotb.test()
async def test_fibonacci_program(dut):
    """Integration test: print the first five Fibonacci numbers."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [
        ldi(1, 1),             # 0: a = 1
        ldi(2, 2),             # 1: b = 2 (1,2,3,5,8 - all distinct on the pins)
        ldi(4, 5),             # 2: 5 iterations
        out(1, 1),             # 3: loop: print a
        add(3, 1, 2),          # 4: c = a + b
        mov(1, 2),             # 5: a = b
        mov(2, 3),             # 6: b = c
        addi(4, 0xFF),         # 7: iterations--
        jnz(4, 3),             # 8: repeat
        HALT,                  # 9
    ]

    seen = await cpu.run_program(program, n_outputs=5)
    assert seen == [0x0101, 0x0202, 0x0303, 0x0505, 0x0808], (
        f"unexpected Fibonacci sequence {[hex(v) for v in seen]}"
    )
    await cpu.assert_halted()


@cocotb.test()
async def test_program_is_truncated_at_halt(dut):
    """The loader stops at the first HALT: later words are never executed."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [
        ldi(1, 0x11),          # 0
        out(1, 1),             # 1: 0x1111
        HALT,                  # 2: loading stops here
        ldi(2, 0xDE),          # 3: must never run
        out(2, 2),             # 4: would print 0xDEDE
    ]

    seen = await cpu.run_program(program, n_outputs=1)
    assert seen == [0x1111], f"unexpected OUT sequence {[hex(v) for v in seen]}"
    halted_value = await cpu.assert_halted(stable_cycles=40)
    assert halted_value == 0x1111, "instructions after HALT were executed"


@cocotb.test()
async def test_full_instruction_memory(dut):
    """A 127 word program fills the memory; word 127 is forced to HALT."""
    cpu = Aceputer(dut)
    await cpu.start()

    program = [ldi(1, 0xAB)] * 126 + [out(1, 1)]

    assert len(program) == MAX_PROGRAM_WORDS
    seen = await cpu.run_program(program, n_outputs=1)
    assert seen == [0xABAB], f"unexpected OUT value {hex(seen[0])}"

    # word 127 is generated by the CPU itself, so the program ends in HALT
    halted_value = await cpu.assert_halted(stable_cycles=40)
    assert halted_value == 0xABAB, f"halted output is {hex(halted_value)}"
