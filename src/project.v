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
// right to left, 4 bits for opcode, 3 bits for destination register for load and load high, 8 for actual value
// arithmetic right to left 4 bits for opcode, 3 bits for destination register, 3 bits for source register, 6 reserved

reg [1:0] state, next_state;
localparam PROGRAM = 2'B00,
           EXECUTE = 2'B01,
           HALT    = 2'B10;
           READ_WAIT = 2'B11;

localparam a = 2'b000,
           b = 2'b001,
           c = 2'b010,
           d = 2'b011;
           e = 2'b100;
           f = 2'b101;
           g = 2'b110;
           h = 2'b111;


// Instruction memory and program counter
reg [4:0] pc = 5'd0; // program counter
reg [15:0] instruction_memory [0:31]; // 32 instructions of 16 bits each
reg [5:0] write_pointer = 5'd0;      // points to the next instruction to be written in instruction memory


// Instruction decoding
wire [15:0] program_word = {uio_in[7:0], ui_in[7:0]}; // 16-bit instruction word from inputs
wire [15:0] instruction = instruction_memory[pc]; // instruction input
wire [3:0] OP_CODE = instruction[15:12]; // opcode is upper 4 bits of instruction

// Registers for operands and output
reg [15:0] reg_file [7:0]; //operands
reg_file[0] = 16'h0000; // register x0 read only to 0

reg  [31:0] output_reg; //since output is actually 16 bits, it will require two clock cycles to output the value if the number is greater than 2^16

wire [2:0] rs1, rs2, rd;
assign rd   = instruction[11:9]; //
assign rs1  = instruction[8:6];
assign rs2  = instruction[5:3];
reg [15:0] mov_value;


reg write_en = instruction[3]; // flag to enable writing to instruction memory


// SRAM 
wire sram_str  = rst_n && (state != READ_WAIT) && (OP_CODE == `OP_STORE); // flag for writing to sram, active high
wire sram_read = rst_n && (state == READ_WAIT) && (OP_CODE == `OP_LOAD); // flag for reading from sram, active high
wire [7:0] sram_dout; // data output from sram, prolly will go to reg b
wire [7:0] sram_store; // address to store data in sram, lower 8 bits of instruction
reg read_16bit_flag = 0; //check if read from sram gets a 8 or 16 bit value. default to 0. 0 = 8 bits, 1 = 16 bits;
reg write_16bit_flag = 0;

gf180mcu_ocd_ip_sram___sram256x8mwm1 m_sram (
  .CLK  (clk)  // clock
  .A    (sram_store)  // address
  .D    (reg_file[rd])  // put data from register a into sram
  .Q    (sram_dout)
  .CEN  (!(sram_str || sram_read))  // sram en, active low
  .GWEN (!(sram_str))  // sram write en, active low
  .WEN  (8'b00000000) // might change this, allows rewriting of all bits
);





always @(posedge clk) begin
  
  if (!rst_n) begin
    for (i = 0; i < 16; i = i + 1) begin
      reg_file[i] = 16'd0;
    end
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
        if (rd != 3'b000) begin // 4 bits for opcode, 3 bits for reg 1, 3 bits for reg 2, 3 bits destination reg, 3 bits reserved
         `OP_ADD:     reg_file[rd] <= reg_file[rs1] + reg_file[rs2];
         `OP_SUB:     reg_file[rd] <= reg_file[rs1] - reg_file[rs2];
         `OP_MUL:     reg_file[rd] <= reg_file[rs1] * reg_file[rs2];       
         `OP_ADDI:  begin
          if (instruction[0] == 0)
            reg_file[rd] <= reg_file[rd] + instruction[8:1]; // TO SUBTRACT, JUST ADDI A VALUE SUCH THAT IT OVERFLOWS AND EFFECTIVELY SUBTRACTS
         end   
        end
         `OP_LDI:   begin
          if (instruction[0] == 1'b0) begin
            reg_file[rd][7:0]  <= instruction[8:1];
          end
          if (instruction[0] == 1'b1) begin
            reg_file[rd][15:8] <= instruction[8:1];
          end
         end          
         `OP_STORE:;                                   //nothing happens
         `OP_LOAD:  begin 
            next_state <= READ_WAIT;  // go to READ_WAIT state to read from sram
            if (instruction[0] == 1)begin
              16bit_read = 1'b1;
            end      
         end      
         `OP_MOV: begin
          reg_file[instruction[11:9]] <= reg_file[instruction[8:6]];
         end
         `OP_SHL: reg_file[rd] <= reg_file[rd] << 1; // shift left
         `OP_SHR: reg_file[rd] <= reg_file[rd] >> 1; // shift right
         `OP_HALT: state <= HALT; // halt the processor

         `OP_JZ: if (rd == 16'h0000) pc <= instruction[8:4]; // jump to address in instruction if a is zero, 6:2 because there are only 32 instructions, so use [8:4]
         `OP_JNZ: if (rd != 16'h0000) pc <= instruction[6:2]; // jump to address in instruction if a is not zero

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
       reg_file[rd] <= sram_dout;  // read data from sram into register b
       next_state <= EXECUTE; // reset reading flag after reading from sram
     end
     HALT: begin
        // do nothing, halt the processor
      end
   endcase
endmodule
