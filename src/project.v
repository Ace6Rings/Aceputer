/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
`include "defines.vh"
wire [11:0] instruction = {uio_in[3:0], ui_in[7:0]};// instruction input

reg [3:0] OP_CODE = instruction[11:8]; // opcode is upper 4 bits of instruction
reg [7:0] a, b; //operands

reg reading // flags for reading sram

reg sram_str = rst_n && !reading && (OP_CODE == 'OP_STORE); // flag for writing to sram, active high
reg sram_read = rst_n && reading && (OP_CODE == 'OP_LOAD); // flag for reading from sram, active high

//SRAM

wire [7:0] sram_dout; // data output from sram, prolly will go to reg b

gf180mcu_ocd_ip_sram___sram256x8mwm1 m_sram (
  .CLK  (clk)  // clock
  .A    (instruction[7:0])  // address
  .D    (a)  // put data from register a into sram
  .Q    (sram_dout)
  .CEN  (!(sram_str || sram_read))  // sram en, active low
  .GWEN (!(sram_str))  // sram write en, active low
  .WEN  (8'b00000000) // might change this, but rn it js doesn't overwrite anything
);


always @(posedge clk) begin
  case (OP_CODE)begin
    'OP_add:     a <= a + b;
    'OP_sub:     a <= a - b;
    'OP_ADDI:    a <= a + instruction[7:0];           // TO SUBTRACT, JUST ADDI A VALUE SUCH THAT IT OVERFLOWS AND EFFECTIVELY SUBTRACTSa <= a + ui_in[7:0]; 
    'OP_LDI:     a <= instruction[7:0];           // load immediate value into register a
    'OP_STORE:   sram_str <= instruction[7:0];  // enable write to sram, instruction[7:0] is the address to write to, also is the lowwer 8 bits of the instruction
    'OP_LOAD:    b <= sram_dout;                // load data from sram into register b
    default: begin
      a <= 8'h00;
      b <= 8'h00;
    end
    endcase
end

endmodule
