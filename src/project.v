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

`include "defines.vh"


localparam [2:0] PROGRAM       = 3'b000,
                 EXECUTE       = 3'b001,
                 HALT          = 3'b010,
                 MEM_WAIT      = 3'b011,
                 OUTPUT        = 3'b100,
                 PROGRAM_WRITE = 3'b101,
                 PROGRAM_READ  = 3'b110; //program read, write, and memwait does the same stuff. maybe simplify later
integer i;
reg [2:0] state;

// Instruction memory and program counter
reg [6:0] pc; // program counter
reg [6:0] write_pointer;    // points to the next instruction to be written in instruction memory
reg instruction_complete;
// Instruction decoding
wire [15:0] program_word = {uio_in[7:0], ui_in[7:0]}; // 16-bit instruction word from inputs
reg [15:0] out;
assign {uio_out[7:0], uo_out[7:0]} = out;
wire [15:0] instruction = instruction_reg[0]; // instruction input
wire [3:0] OP_CODE = instruction[15:12]; // opcode is upper 4 bits of instruction

// Registers for operands and output
reg [7:0] reg_file [7:0]; //operands
reg  [15:0] output_reg;

// operands
wire [2:0] rs1, rs2, rd;
assign rd   = instruction[11:9]; 
assign rs1  = instruction[8:6];
assign rs2  = instruction[5:3];


// SRAM 
sram_controller u_sram_ctrl (
    .clk       (clk),
    .rst_n     (rst_n),
    .req_valid (req_valid),
    .req_addr  (req_addr),
    .req_wdata (req_wdata),
    .req_type  (req_type),
    .resp_done (resp_done),
    .req_rdy   (req_rdy),
    .out_rdy   (out_rdy),
    .sram_out  (sram_out)
);


wire [6:0] prefetch_word_addr = prefetch_start ? (instruction_complete ? pc : pc + 7'd1) : prefetch_reg;

reg [7:0] sram_store;
reg [6:0] prefetch_reg;

reg prefetch_buffer_valid;

wire prefetch_start =
    rst_n &&
    (state == EXECUTE) &&
    !prefetch_flag &&
    !prefetch_pending &&
    !prefetch_buffer_valid &&
    (instruction_complete ||
     ((OP_CODE != `OP_LOAD) &&
      (OP_CODE != `OP_STORE) &&
      (OP_CODE != `OP_HALT) &&
      (OP_CODE != `OP_JZ) && //updates pc before prefetching so its chill
      (OP_CODE != `OP_JNZ)));
wire prefetch_issue = prefetch_start || prefetch_flag;

//uio_oe 
reg [7:0] uio_oe_reg;
assign uio_oe = uio_oe_reg; 
reg carry;
wire [8:0] add_sum = {1'b0, reg_file[rs1]} + {1'b0, reg_file[rs2]} + (instruction[0] ? {8'd0, carry} : 9'd0); //INSTRUCTION[0] DIFFERENTIATES BETWEEN ADD AND ADD WITH NO CARRY TO PREVENT ADDING 1'd1 TO THE NEXT ADD INSTRUCTION THAT IS UNRELATTED

//WRITE PROGRAM TO MEMORY

reg [15:0] instruction_reg[1:0]; //instruction reg
reg OP_HALT_FLAG; //0 if opcode is NOT OP_HALT, 1 if it is.

always @ (*) begin
  
end
always @(posedge clk) begin
  if (!rst_n) begin
    for (i = 0; i < 8; i = i + 1) begin
      reg_file[i] <= 8'd0;
    end
    state <= PROGRAM;
    pc <= 8'd0;
    write_pointer <= 7'd0;
    instruction_complete <= 1'b0; 
    prefetch_reg <= 7'd0;
    prefetch_flag <= 1'b0;
    prefetch_pending <= 1'b0;
    prefetch_byte_sel_d <= 1'b0;
    prefetch_buffer_valid <= 1'b0;
    OP_HALT_FLAG <= 1'b0;
    output_reg <= 16'h000;
    uio_oe_reg <= 8'h00; // default to input
    out <= 16'h000;
    carry <= 1'b0;
  end
  
  else begin
    case (state)
     PROGRAM: begin  // THE HOST MUST HOLD THE INSTRUCTION FOR 2 CLOCK CYCLES
      if (write_pointer == 7'd127) begin
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
       if (instruction_complete) begin
         if (prefetch_buffer_valid) begin
           instruction_reg[0] <= instruction_reg[1];
           prefetch_buffer_valid <= 1'b0;
           instruction_complete <= 1'b0;
         end
       end
       else begin
        if ((OP_CODE != `OP_LOAD) && (OP_CODE != `OP_HALT))
          pc <= pc + 1'b1;
        if ((OP_CODE != `OP_OUT) && (OP_CODE != `OP_HALT))
          uio_oe_reg <= 8'h00;

        case (OP_CODE)
         `OP_ADD: begin 
          carry <= add_sum[8];
          if (rd != 3'b000)
             reg_file[rd] <= add_sum[7:0];
         end
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

         `OP_JZ: if (reg_file[rd] == 8'h00) pc <= instruction[8:2]; //7 bits long cuz pc is 7 bits long cuz i only have 256 bytes of ram, so max 128 instructions.
         `OP_JNZ: if (reg_file[rd] != 8'h00) pc <= instruction[8:2]; 
         `OP_OUT: begin
          output_reg <= {reg_file[rs1], reg_file[rs2]};
          state <= OUTPUT;
         end
         default:; //does jack shit
        endcase

        if (OP_CODE != `OP_HALT) begin // CHECK IF REG 1 IS A VALID INSTRUCTION. IF NOT, THEN IT STALLS THE CPU.
          if (prefetch_buffer_valid &&
              (OP_CODE != `OP_LOAD) &&
              (OP_CODE != `OP_JZ) &&
              (OP_CODE != `OP_JNZ)) begin
            instruction_reg[0] <= instruction_reg[1];
            prefetch_buffer_valid <= 1'b0; //resets to 0
          end
          else begin
            instruction_complete <= 1'b1; //sets it to 1 if instruction is completed. this stalls the cpu if it continues to be 1.
          end
        end
       end
      end
     READ_WAIT: begin
      state <= READ_CAPTURE;
     end
     READ_CAPTURE: begin
        if (program_read_active) begin
          if (!byte_sel) begin
            instruction_reg[0][7:0] <= sram_dout;
            byte_sel <= 1'b1;
            state <= PROGRAM_READ;
          end
          else begin
            instruction_reg[0][15:8] <= sram_dout;
            byte_sel <= 1'b0;
            program_read_active <= 1'b0;
            state <= EXECUTE;
          end
        end
        else begin
          if (rd != 3'b000) begin
            reg_file[rd] <= sram_dout;  // register zero is read-only
          end
          pc <= pc + 1'b1;
          state <= EXECUTE;
        end
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
          byte_sel <= 1'b1;
        end
        1'b1: begin
          byte_sel <= 1'b0;
          state <= PROGRAM;
          write_pointer <= write_pointer + 7'd1;
        end
       endcase
       if (OP_HALT_FLAG == 1'b1 && (byte_sel == 1'b1)) begin //fix byte_sel logic later
        state <= PROGRAM_READ;
        byte_sel <= 1'b0;
        pc <= 7'd0;
        program_read_active <= 1'b1;
       end
     end
     PROGRAM_READ: begin //basically just used to start the program
      state <= READ_CAPTURE;
     end 
      default: begin
        state <= HALT;
      end
   endcase


   //PREFETCHING

if (prefetch_pending) begin //edge 2, sram_dout is already going to be valid data cuz it was requested 1 clock cycle before
  if (!prefetch_byte_sel_d) begin
    instruction_reg[1][7:0] <= sram_dout;
  end
  else begin
    instruction_reg[1][15:8] <= sram_dout; //edge 3
    prefetch_buffer_valid <= 1'b1;
  end
end

prefetch_pending <= prefetch_issue; //edge 1

if (prefetch_issue) begin 
  prefetch_byte_sel_d <= byte_sel; //stores the requested byte_sel
  if (!byte_sel) begin // requests the low byte
    byte_sel <= 1'b1;  // makes it request the high byte next rising edge
    prefetch_flag <= 1'b1; 
    if (prefetch_start)
      prefetch_reg <= prefetch_word_addr; //sends shit
  end
  else begin
    byte_sel <= 1'b0; 
    prefetch_flag <= 1'b0;
  end
end
  end
end
endmodule
