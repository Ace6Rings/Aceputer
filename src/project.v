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
reg  [15:0] out;
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
reg req_valid;
reg  [7:0] req_addr;
reg  [15:0]req_wdata;
reg  [1:0] req_type;
reg  prefetch_active;
wire resp_done = out_rdy;
wire req_rdy;
wire out_rdy;
wire [15:0] sram_out;


wire [6:0] prefetch_word_addr = instruction_complete ? pc : (pc + 7'd1);




reg prefetch_buffer_valid;

wire prefetch_start =
    rst_n &&
    (state == EXECUTE) &&
    req_rdy &&
    !req_valid &&
    !prefetch_active &&
    !prefetch_buffer_valid &&
    (instruction_complete ||
     ((OP_CODE != `OP_LOAD) &&
      (OP_CODE != `OP_STORE) &&
      (OP_CODE != `OP_HALT) &&
      (OP_CODE != `OP_JZ) && //updates pc before prefetching so its chill
      (OP_CODE != `OP_JNZ)));


//uio_oe 
reg [7:0] uio_oe_reg;
assign uio_oe = uio_oe_reg; 
reg carry;
wire [8:0] add_sum = {1'b0, reg_file[rs1]} + {1'b0, reg_file[rs2]} + (instruction[0] ? {8'd0, carry} : 9'd0); //INSTRUCTION[0] DIFFERENTIATES BETWEEN ADD AND ADD WITH NO CARRY TO PREVENT ADDING 1'd1 TO THE NEXT ADD INSTRUCTION THAT IS UNRELATTED

//WRITE PROGRAM TO MEMORY

reg [15:0] instruction_reg[1:0]; //instruction reg
reg OP_HALT_FLAG; //0 if opcode is NOT OP_HALT, 1 if it is.

always @(posedge clk) begin
  if (!rst_n) begin
    for (i = 0; i < 8; i = i + 1) begin
      reg_file[i] <= 8'd0;
    end
    state <= PROGRAM;
    pc <= 7'd0;
    write_pointer <= 7'd0;
    req_valid <= 1'b0;
    req_addr <= 8'd0;
    req_wdata <= 16'd0;
    req_type  <= 2'b00;
    prefetch_active <= 1'b0;
    instruction_complete <= 1'b0; 
    prefetch_buffer_valid <= 1'b0;
    OP_HALT_FLAG <= 1'b0;
    output_reg <= 16'h000;
    uio_oe_reg <= 8'h00; // default to input
    out <= 16'h000;
    carry <= 1'b0;
  end
  
  else begin
    if (req_valid && req_rdy)
        req_valid <= 1'b0;
    case (state)
     PROGRAM: begin
    if (req_rdy && !req_valid) begin
        req_valid <= 1'b1;
        req_type  <= 2'b01; // WRITE_WORD
        req_addr  <= {write_pointer, 1'b0};
        req_wdata <= (write_pointer == 7'd127) ? {`OP_HALT, 12'd0} : program_word;
        state     <= PROGRAM_WRITE;

        if (write_pointer == 7'd127) begin
            instruction_reg[0] <= {`OP_HALT, 12'b000000000000};
            OP_HALT_FLAG       <= 1'b1;
        end else begin
            instruction_reg[0] <= program_word;
            if (program_word[15:12] == `OP_HALT)
                OP_HALT_FLAG <= 1'b1;
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
        if ((OP_CODE != `OP_LOAD) && (OP_CODE != `OP_STORE) && (OP_CODE != `OP_HALT))
          pc <= pc + 7'd1;
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
         `OP_STORE: begin
                      if (req_rdy && !req_valid && !prefetch_active) begin
                        req_valid <= 1'b1;
                        req_type  <= 2'b11; // WRITE_BYTE
                        req_addr  <= instruction[8:1];
                        req_wdata <= {8'd0, reg_file[rd]};
                        state     <= MEM_WAIT;
                      end
         end
         `OP_LOAD: begin
                     if (req_rdy && !req_valid && !prefetch_active) begin
                        req_valid <= 1'b1;
                         req_type  <= 2'b10; // READ_BYTE
                         req_addr  <= instruction[8:1];
                         state     <= MEM_WAIT;
                     end
         end
        
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

        if ((OP_CODE != `OP_HALT) && (OP_CODE != `OP_LOAD) && (OP_CODE != `OP_STORE)) begin
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
     if (prefetch_active && out_rdy) begin
               instruction_reg[1] <= sram_out;
               prefetch_buffer_valid <= 1'b1;
               prefetch_active <= 1'b0;
          end
          
     if (prefetch_start) begin
               req_valid  <= 1'b1;
               req_type   <= 2'b00; // READ_WORD
               req_addr   <= {prefetch_word_addr, 1'b0};
               prefetch_active <= 1'b1;
     end
  end
  
     MEM_WAIT: begin
       if (out_rdy) begin
         if ((OP_CODE == `OP_LOAD) && (rd != 3'b000))
           reg_file[rd] <= sram_out[7:0];
         pc <= pc + 7'd1;
         if (prefetch_buffer_valid) begin
           instruction_reg[0]    <= instruction_reg[1];
           prefetch_buffer_valid <= 1'b0;
           instruction_complete  <= 1'b0;
         end 
         else begin
           instruction_complete  <= 1'b1;
         end
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
       if (out_rdy) begin
         if (OP_HALT_FLAG == 1'b1) begin
           pc        <= 7'd0;
           req_valid <= 1'b1;
           req_type  <= 2'b00; // READ_WORD
           req_addr  <= 8'd0;
           state     <= PROGRAM_READ;
         end 
         else begin
           write_pointer <= write_pointer + 7'd1;
           state <= PROGRAM;
         end
       end
     end
     PROGRAM_READ: begin
           if (out_rdy) begin
           instruction_reg[0]   <= sram_out;
           instruction_complete <= 1'b0;
           state <= EXECUTE;
           end
     end
     default: state <= HALT;
    endcase
  end
end
endmodule
