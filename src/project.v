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


reg [1:0] state, next_state;
localparam PROGRAM = 2'B00,
           EXECUTE = 2'B01,
           HALT    = 2'B10;
           READ_WAIT = 2'B11;



wire [11:0] instruction = {uio_in[3:0], ui_in[7:0]};// instruction input

wire [3:0] OP_CODE = instruction[11:8]; // opcode is upper 4 bits of instruction
reg  [7:0] a, b; //operands
reg  [7:0] output_reg; 


wire sram_str  = rst_n && (state != READ_WAIT) && (OP_CODE == 'OP_STORE); // flag for writing to sram, active high
wire sram_read = rst_n && (state == READ_WAIT) && (OP_CODE == 'OP_LOAD); // flag for reading from sram, active high

//SRAM

wire [7:0] sram_dout; // data output from sram, prolly will go to reg b
wire [7:0] sram_store; // address to store data in sram, lower 8 bits of instruction

gf180mcu_ocd_ip_sram___sram256x8mwm1 m_sram (
  .CLK  (clk)  // clock
  .A    (sram_store)  // address
  .D    (a)  // put data from register a into sram
  .Q    (sram_dout)
  .CEN  (!(sram_str || sram_read))  // sram en, active low
  .GWEN (!(sram_str))  // sram write en, active low
  .WEN  (8'b00000000) // might change this, allows rewriting of all bits
);


always @(posedge clk) begin
  
  if (!rst_n) begin
    a <= 8'h00;
    b <= 8'h00;
    output_reg <= 8'h00;
    reading <= 1'b0;
  end
  case (state)
    PROGRAM: begin
      if (OP_CODE == 'OP_LOAD) begin
        reading <= 1'b1; // set reading flag when load instruction is encountered
      end
    end
    EXECUTE: begin
      case (OP_CODE)begin
        'OP_add:     a <= a + b;
        'OP_sub:     a <= a - b;
        'OP_ADDI:    a <= a + instruction[7:0];       // TO SUBTRACT, JUST ADDI A VALUE SUCH THAT IT OVERFLOWS AND EFFECTIVELY SUBTRACTS
        'OP_LDI:     a <= instruction[7:0];           // load immediate value into register a
        'OP_STORE:;                                   //nothing happens
        'OP_LOAD:    reading <= 1'b1;

        'OP_OUT:  output_reg <= a;                    // output value of register a to output register


         default: begin
            a <= 8'h00;
            b <= 8'h00;
         end
      endcase
        
      end else begin
        state <= PROGRAM; // go back to PROGRAM state after execution
      end
    end
    READ_WAIT: begin
      if (!reading) begin
        state <= PROGRAM; // go back to PROGRAM state after reading from sram
      end
    end
    HALT: begin
      // do nothing, halt the processor
    end

  else begin
    b <= sram_dout;  // read data from sram into register b
    reading <= 1'b0; // reset reading flag after reading from sram
  end

  
end


endmodule
