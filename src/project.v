/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_Ace6Rings (
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
/* verilator lint_off UNUSEDSIGNAL */
    wire instruction[0];
/* verilator lint_off UNUSEDSIGNAL */


`include "defines.vh"


localparam [2:0] PROGRAM   = 3'b000,
                 EXECUTE   = 3'b001,
                 HALT      = 3'b010,
                 READ_WAIT = 3'b011,
                 READ_CAPTURE = 3'b100, // wait for sram to send data back before reading sram_dout
                 OUTPUT = 3'b101,
                 PROGRAM_WRITE= 3'110;
                 PROGRAM_READ = 3'b111;
integer i;
reg [2:0] state;

// Instruction memory and program counter
reg [6:0] pc; // program counter
reg [6:0] write_pointer;    // points to the next instruction to be written in instruction memory
// Instruction decoding
wire [15:0] program_word = {uio_in[7:0], ui_in[7:0]}; // 16-bit instruction word from inputs
reg [15:0] out;
assign {uio_out[7:0], uo_out[7:0]} = out;
wire [15:0] instruction = instruction_reg[0]; // instruction input
wire [3:0] OP_CODE = instruction[15:12]; // opcode is upper 4 bits of instruction
reg instruction_buffer_valid_flag; //shorten this name later ig
// Registers for operands and output
reg [7:0] reg_file [7:0]; //operands
reg  [15:0] output_reg;

// operands
wire [2:0] rs1, rs2, rd;
assign rd   = instruction[11:9]; 
assign rs1  = instruction[8:6];
assign rs2  = instruction[5:3];


// SRAM 
wire [7:0] sram_dout; // data output from sram
wire sram_str  = rst_n && (state != READ_WAIT) && ((state == EXECUTE && OP_CODE == `OP_STORE) || state == PROGRAM_WRITE); // flag for writing to sram, programs stored in sram.
wire sram_read = rst_n && ((prefetch_flag == 1'b1) || (state == PROGRAM_READ) || ((state == READ_WAIT) && (OP_CODE == `OP_LOAD))); // flag for reading from sram, active high
wire [7:0] sram_addr, sram_din;
assign sram_din = (state == PROGRAM_WRITE) ? (byte_sel ? instruction_reg[0][15:8] : instruction_reg[0][7:0]) : reg_file[rd];
assign sram_addr = (state == PROGRAM_WRITE) ? {write_pointer, byte_sel} :
                   ((state == PROGRAM_READ) ? {pc, byte_sel} :
                   ((prefetch_flag || prefetch_pending) ? {prefetch_reg, byte_sel} : instruction[8:1]));
reg [7:0] sram_store;
reg [6:0] prefetch_reg;
reg prefetch_flag;
reg prefetch_pending;


gf180mcu_ocd_ip_sram__sram256x8m8wm1 sram_inst (
  .CLK  (clk),  // clock
  .A    (sram_addr),  // address
  .D    (sram_din),  // put data from register a into sram
  .Q    (sram_dout),
  .CEN  (!(sram_str || sram_read)),  // sram en, active low
  .GWEN (!(sram_str)),  // sram write en, active low
  .WEN  (8'b00000000)  // might change this, allows rewriting of all bits
);

//uio_oe 
reg [7:0] uio_oe_reg;
assign uio_oe = uio_oe_reg; 

//WRITE PROGRAM TO MEMORY

wire [15:0] splitted_instruction = instruction_reg[0] //only zero, the other reg is useful for reading programs
wire [7:0]  top_byte    = word_to_split[15:8];
wire [7:0]  bottom_byte = word_to_split[7:0];
reg byte_sel; // 0 = low byte, 1 = high byte
reg [15:0] instruction_reg[1:0]; //instruction reg
reg OP_HALT_FLAG; //0 if opcode is NOT OP_HALT, 1 if it is.


always @(posedge clk) begin
  if (!rst_n) begin
    for (i = 0; i < 8; i = i + 1) begin
      reg_file[i] <= 8'd0;
    end
    state <= PROGRAM;
    pc <= 8'd0;
    write_pointer <= 7'd0;
    byte_sel <= 1'b0;
    instruction_buffer_valid_flag <= 1'b0;
    prefetch_reg <= 7'd0;
    prefetch_flag <= 1'b0;
    prefetch_pending <= 1'b0;
    output_reg <= 16'h000;
    uio_oe_reg <= 8'h00; // default to input
    out <= 16'h000;
  end
  
  else begin
    case (state)
     PROGRAM: begin  // THE HOST MUST HOLD THE INSTRUCTION FOR 2 CLOCK CYCLES
      if (write_pointer == xx) begin //change xx 
        instruction_reg[0] <= {`OP_HALT, 12'b000000000000}; // force last instruction to be a halt
        state <= PROGRAM_WRITE;
        OP_HALT_FLAG <= 1'b1;
      
      end
      else begin
        instruction_reg[0] <= program_word; // write instruction to instruction memory
        if (program_word[15:12] == `OP_HALT) begin
          OP_HALT_FLAG <= 1'b1; 
          state <= PROGRAM_WRITE;
        end
        else begin
       
         state <= PROGRAM_WRITE;
        end
      end
      
     end
     EXECUTE: begin
        if ((OP_CODE != `OP_LOAD) && (OP_CODE != `OP_HALT))
          pc <= pc + 1'b1;
        if ((OP_CODE != `OP_OUT) && (OP_CODE != `OP_HALT))
          uio_oe_reg <= 8'h00;

        case (OP_CODE)
         `OP_ADD: if (rd != 3'b000)
                    reg_file[rd] <= reg_file[rs1] + reg_file[rs2];
         `OP_SUB: if (rd != 3'b000)
                    reg_file[rd] <= reg_file[rs1] - reg_file[rs2];
         `OP_ADDI:  begin
          if (rd != 3'b000)
            reg_file[rd] <= reg_file[rd] + instruction[8:1]; // TO SUBTRACT, JUST ADDI A VALUE SUCH THAT IT OVERFLOWS AND EFFECTIVELY SUBTRACTS
         end
         `OP_AND: if(rd != 3'b000)
                   reg_file[rd] <= reg_file[rs1] & reg_file[rs2];
         `OP_XOR: if(rd != 3'b000)
                   reg_file[rd] <= reg_file[rs1] ^ reg_file[rs2];   
         `OP_COMP:if(rd != 3'b000)
                   reg_file[rd] <= {7'b0000000, (reg_file[rs1] == reg_file[rs2])};
         `OP_LDI: if (rd != 3'b000)
                    reg_file[rd] <= instruction[8:1];
         `OP_STORE: sram_store <= instruction[8:1];   //nothing happens                    
         `OP_LOAD: state <= READ_WAIT;  // go to READ_WAIT state to read from sram
         
         
               
         `OP_MOV: begin
          if (rd != 3'b000)
            reg_file[rd] <= reg_file[rs1];
         end
         `OP_SHL: if (rd != 3'b000)
                    reg_file[rd] <= reg_file[rd] << 1; // shift left
         `OP_SHR: if (rd != 3'b000)
                    reg_file[rd] <= reg_file[rd] >> 1; // shift right
         `OP_HALT: state <= HALT; // halt the processor

         `OP_JZ: if (reg_file[rd] == 8'h00) pc <= instruction[8:4]; 
         `OP_JNZ: if (reg_file[rd] != 8'h00) pc <= instruction[8:4]; 
         `OP_OUT: begin
          output_reg <= {reg_file[rs1], reg_file[rs2]};
          state <= OUTPUT;
         end
         default:; //does jack shit
        endcase
      end
     READ_WAIT: begin
      state <= READ_CAPTURE;
     end
     READ_CAPTURE: begin
      if (rd != 3'b000) begin
        reg_file[rd] <= sram_dout;  // register zero is read-only
      end
      pc <= pc + 1'b1;
      state <= EXECUTE;
     end

     OUTPUT: begin
      uio_oe_reg <= 8'hFF;
      out <= output_reg;
      state <= EXECUTE;
     end

     HALT: begin
      out <= output_reg;
      uio_oe_reg <= 8'hFF; //switch them to output
        // output the output_reg indefinitely
      end
     PROGRAM_WRITE: begin
       case (byte_sel) //one bit reg that specifies if the write is low byte or high
        1'b0: begin
          byte_sel <= !byte_sel;
        end
        1'b1: begin
          byte_sel <= !byte_sel;
          state <= PROGRAM;
          write_pointer <= write_pointer + 7'd1;
        end
       endcase
       if (OP_HALT_FLAG == 1'b1 && (byte_sel == 1'b1)) begin //fix byte_sel logic later
        state <= PROGRAM_READ
       end
     end
     PROGRAM_READ: begin //basically just used to start the program
      case (byte_sel)
        1'b0: begin
          instruction_reg[0][7:0] <= sdram_out;
          byte_sel <= byte_sel!;
        end
        1'b1: begin
          instruction_reg[0][15:8] <= sdram_out;
          byte_sel <= byte_sel!;
          pc <= pc + 1'd1;
          instruction_buffer_valid_flag = 1'b1;
        end
      endcase
     end 
      default: begin
        state <= HALT;
      end
   endcase
   if (prefetch_flag) begin
    prefetch_flag <= 1'b0;
    prefetch_pending <= 1'b1;
    case (byte_sel)
      1'b0: begin
        instruction_reg[1][7:0] = sram_dout;
        byte_sel != byte_sel;
      end
      1'b1: begin
        instruction_reg[1][15:8] = sram_dout;
        byte_sel != byte_sel;
      end
    endcase

   end


end
endmodule
