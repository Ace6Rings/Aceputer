// SPDX-License-Identifier: Apache-2.0
//
// Behavioral (RTL-simulation only) model of the GF180 MCU 256x8 SRAM macro
// that `project.v` instantiates as `sram_inst`.
//
// The real hard macro only exists as a GDS/LEF/LIB blackbox in the PDK, so the
// RTL testbench needs this model to elaborate. It is NOT part of the design and
// must never be added to `source_files` in info.yaml.
//
// Timing matches the macro's "read-during-write" behaviour: one clock of read
// latency, Q holds while CEN is high, and a write returns the *old* contents.
`default_nettype none

module gf180mcu_ocd_ip_sram__sram256x8m8wm1 (
  input  wire       CLK,
  input  wire [7:0] A,
  input  wire [7:0] D,
  output reg  [7:0] Q,
  input  wire       CEN,
  input  wire       GWEN,
  input  wire [7:0] WEN,
  input  wire       VDD,
  input  wire       VSS
);

  reg [7:0] mem [0:255];

  always @(posedge CLK) begin
    if (!CEN) begin
      if (!GWEN) begin
        mem[A] <= D & ~WEN;  // WEN is active low per bit
      end
      Q <= mem[A];
    end
  end

endmodule

`default_nettype wire
