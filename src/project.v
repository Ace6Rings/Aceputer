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
// right to left, 4 bits for opcode, 2 bits for destination register for load and load high, 8 for actual value, 2 reserved

reg [1:0] state, next_state;
localparam PROGRAM = 2'B00,
           EXECUTE = 2'B01,
           HALT    = 2'B10;
           READ_WAIT = 2'B11;

reg [4:0] pc = 5'd0; // program counter
reg [15:0] instruction_memory [0:31]; // 32 instructions of 16 bits each
reg [5:0] write_pointer = 5'd0;      // points to the next instruction to be written in instruction memory

wire [15:0] program_word = {uio_in[7:0], ui_in[7:0]}; // 16-bit instruction word from inputs
wire [15:0] instruction = instruction_memory[pc]; // instruction input
wire [3:0] OP_CODE = instruction[15:12]; // opcode is upper 4 bits of instruction


reg  [15:0] a, b, c, d;//operands
reg  [15:0] output_reg; 

wire [1:0] mov_dest = instruction[11:10];
wire [1:0] mov_src  = instruction[9:8];

reg [15:0] mov_value;


reg write_en = instruction[3]; // flag to enable writing to instruction memory


wire sram_str  = rst_n && (state != READ_WAIT) && (OP_CODE == `OP_STORE); // flag for writing to sram, active high
wire sram_read = rst_n && (state == READ_WAIT) && (OP_CODE == `OP_LOAD); // flag for reading from sram, active high

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



always @(*) begin
  case (mov_src)
    2'b00: mov_value <= a;
    2'b01: mov_value <= b;
    2'b10: mov_value <= c;
    2'b11: mov_value <= d;
  endcase
end

always @(posedge clk) begin
  
  if (!rst_n) begin
    a <= 16'h0000;
    b <= 16'h0000;
    c <= 16'h0000;
    d <= 16'h0000;
    output_reg <= 16'h0000;
    state <= PROGRAM;
    pc <= 5'd0;
    write_pointer <= 6'd0;
  end
  
  else
    case (state)
      PROGRAM: begin
        if (write_en) begin
         instruction_memory[write_pointer] <= program_word; // write instruction to instruction memory
         write_pointer <= write_pointer + 1'b1; // increment write pointer
        end
        else begin
         state <= EXECUTE; // go to EXECUTE state after writing all instructions
        end
      end

      end
     EXECUTE: begin
        case (OP_CODE)
         `OP_ADD:     a <= a + b;
         `OP_SUB:     a <= a - b;
         `OP_MUL:     a <= a * b;
         `OP_ADDI:    a <= a + instruction[9:2];       // TO SUBTRACT, JUST ADDI A VALUE SUCH THAT IT OVERFLOWS AND EFFECTIVELY SUBTRACTS
         `OP_LDI:     a [7:0]  <= instruction[9:2];           // load immediate value into register a
         `OP_LDIH:    a [15:8] <= instruction[9:2];          // load immediate value into upper 8 bits of register a
         `OP_LDB:     b [7:0]  <= instruction[9:2];
         `OP_STORE:;                                   //nothing happens
         `OP_LOAD:    next_state <= READ_WAIT;         // go to READ_WAIT state to read from sram
         `OP_OUT:  output_reg <= a;                    // output value of register a to output register
         `OP_MOV: begin
            case (mov_dest)
               2'b00: a <= mov_value;
               2'b01: b <= mov_value;
               2'b10: c <= mov_value;
               2'b11: d <= mov_value;
            endcase
         end
         `OP_SHL: a <= a << 1; // shift left
         `OP_SHR: a <= a >> 1; // shift right
         `OP_HALT: state <= HALT; // halt the processor
         `OP_NOP: ; // do nothing
         `OP_JZ: if (a == 16'h0000) pc <= instruction[6:2]; // jump to address in instruction if a is zero, 6:2 because there are only 32 instructions, so use lower 5 bits of the instruction bits
         `OP_JNZ: if (a != 16'h0000) pc <= instruction[6:2]; // jump to address in instruction if a is not zero

         default: begin
            a <= 16'h0000;
            b <= 16'h0000;
            c <= 16'h0000;
            d <= 16'h0000;
         end
      endcase
        
        end else begin
          state <= PROGRAM; // go back to PROGRAM state after execution
        end
      end
     READ_WAIT: begin
       b <= sram_dout;  // read data from sram into register b
       next_state <= EXECUTE; // reset reading flag after reading from sram
     end
     HALT: begin
        // do nothing, halt the processor
      end
   endcase
endmodule
