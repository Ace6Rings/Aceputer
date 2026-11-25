<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works
Aceputer is a 8 bit cpu with a 16 bit wide instruction. It uses the 256x8 GF180MCU SRAM macro (gf180mcu_ocd_ip_sram__sram256x8m8wm1). All logic is handled in one file, and the program is fetched with a prefetcher, which fetches the program from sram at address pc + 1. When state is HALT, the cpu stops and outputs the output register until reset.

## How to test

Set ena = 1 and hold rst_n = 0 for several clock cycles on clk to reset the CPU registers and program counter.
Release reset (rst_n = 1) and drive ui_in with the desired input data while pulsing clk.
Observe the CPU state and output data on uo_out.
Note: when loading a program, the host must hold the instruction for exactly two clock cycles.

## External hardware

List external hardware used in your project (e.g. PMOD, LED display, etc), if any
