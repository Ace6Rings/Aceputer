import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, ReadOnly
@cocotb.test()
async def test_accumulator(dut):
    dut.ena.value = 1
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    # Hold reset for a rising edge, then check the output.
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.uo_out.value) == 0x00, "Reset should clear the output"
    # Release reset and present a byte before the next rising edge.
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.ui_in.value = 0xA5
    await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.uo_out.value) == 0xA5, "The register should load 0xA5"
