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

reg [7:0] a, b; //operands

always @(posedge clk) begin
  case (uio_in[3:0])begin
    'op_add: begin
      a <= a + b;
    end
    'op_sub: begin
      a <= a - b;
    end
    'op_ADDI: begin // TO SUBTRACT, JUST ADDI A VALUE SUCH THAT IT OVERFLOWS AND EFFECTIVELY SUBTRACTS
      a <= a + ui_in[7:0]; 
    end
    'op_LDI: begin
      a <= ui_in[7:0];
    end
    'op_STORE: begin
      
    default: begin
      a <= 8'h00;
      b <= 8'h00;
    end
    endcase
end

endmodule
