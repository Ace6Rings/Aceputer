/*
 * Copyright (c) 2026 Steven Xie
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module sram_controller (
    input   wire      clk,
    input   wire      rst_n,

    input   wire       req_valid,      //1 if cpu requested to do something. switch state to the appropriate thing
    input   wire[7:0]  req_addr, //address
    input   wire[15:0] req_wdata,//write data. 
    input   wire[1:0]  req_type, //least significant bit is read or write, 0 = read, write = 1. most significant bit is req legntth, 0 = 8 bits, 1 = 16 bits
    input   wire       resp_done, //when cpu gets the output, this is pulled high. if pulled high, everything gets wiped

    output  reg        req_rdy,
    output  reg        out_rdy, //see if sram_out is valid. 1 for true, 0 for false. if 1, cpu will take that value. if it is a write, then 1 = write successful, 0 = failed
    output  reg [15:0] sram_out //change this name later, confusing with dout
);
//MEMORY CONTROL HAVE NO SAFEGUARDS, ITS ALL UP TO THE PROGRAMMER
//THIS IS BASED ON LINE 57-96 IN project.v in the MAIN branch
gf180mcu_ocd_ip_sram__sram256x8m8wm1 sram_inst (
  .CLK  (clk),  // clock
  .A    (sram_addr),  // address
  .D    (sram_din),  // put data from register a into sram
  .Q    (sram_dout),
  .CEN  (!(sram_str || sram_read)),  // sram en, active low
  .GWEN (!(sram_str)),  // sram write en, active low
  .WEN  (8'b00000000)  // might change this, allows rewriting of all bits
);
//req_type
localparam [1:0] READ_WORD  = 2'b00,
                 WRITE_WORD = 2'b01,
                 READ_BYTE  = 2'b10, //name is confusing, change later. but it just means it is reading sram for only one cell and is meant to be put in reg_file. basically opcode is load
                 WRITE_BYTE = 2'b11; //basically used for when opcode is store


//states
localparam [2:0] READ_WAIT    = 3'b000,
                 READ_CAPTURE = 3'b001,
                 WRITE        = 3'b010,
                 IDLE         = 3'b100,
                 RESP_WAIT    = 3'b101;
                 
//REGISTERS
reg [7:0] req_addr_reg;
reg [1:0] req_type_reg;
reg [15:0] req_wdata_reg;

// MISC
reg [2:0] state;
//basic functions ig
reg [7:0] sram_addr;
reg sram_str;
reg sram_read;
reg [7:0] sram_din; //for writing

//READ INSTRUCTIONS



// for if req_type[1] is 1. otherwise just output directly

reg     byte_sel, // 1 = high byte, 0 = low byte
        byte_sel_d;//used for prefetching, same logic as before in project.v in main 
    


reg [7:0] low_byte;
// reg [7:0] high_byte;

// for if req_type[1] is 0
wire [7:0] sram_dout;  



always @(posedge clk) begin
    if (!rst_n) begin
        state <= IDLE;
         req_rdy <= 1'b1;
         out_rdy <= 1'b0;
         sram_str <= 1'b0;
         sram_read <= 1'b0;
         byte_sel <= 1'b0;
         byte_sel_d <= 1'b0;


    end
    else begin
        case (state)
            READ_WAIT: begin 
                if (req_type_reg == READ_WORD) begin
                    sram_addr <= req_addr_reg + 8'd1; //change address ahead of time
                    state <= READ_CAPTURE;
                end
                else begin
                    sram_read <= 1'b0;
                    state <= READ_CAPTURE;
                end           
            end 
            READ_CAPTURE: begin
                case (req_type_reg)
                    READ_BYTE: begin //since it is just one byte, just go do it directly.
                        sram_out <= {8'd0, sram_dout[7:0]}; //get the data from sram and put it to the output
                        out_rdy <= 1'b1;
                        state <= RESP_WAIT;

                    end
                    READ_WORD: begin
                        case (byte_sel_d)
                            1'b0:begin
                                  low_byte <= sram_dout [7:0];
                                  byte_sel_d <= 1'b1;
                                  sram_read <= 1'b0;
                                
                            end
                            1'b1: begin
                                  sram_out <= {sram_dout, low_byte};
                                  byte_sel_d <= 1'b0;
                                  out_rdy <= 1'b1;
                                  state <= RESP_WAIT;
                            end
                        endcase  
                    end
                endcase
            end
            WRITE: begin
                case (req_type_reg)
                    WRITE_BYTE: begin
                        out_rdy <= 1'b1;
                        state <= RESP_WAIT;
                        sram_str <= 1'b0;
                    end
                    WRITE_WORD: begin
                        case (byte_sel)
                            1'b0: begin // this is now redundant, since this case should never be true due to the logic in state= HALT
                                sram_str <= 1'b0;
                                out_rdy <= 1'b1;
                                state <= RESP_WAIT;
                            end 
                            1'b1: begin
                                byte_sel  <= 1'b0;
                                sram_addr <= req_addr_reg + 8'd1;
                                sram_din  <= req_wdata_reg[15:8];
                            end
                    endcase
                end
                endcase
            end
            IDLE: begin
                sram_str  <= 0; 
                sram_read <= 0;
                if (req_valid && req_rdy) begin
                req_rdy <= 1'b0;
                req_addr_reg <= req_addr;
                req_type_reg <= req_type;
                req_wdata_reg <= req_wdata; // UPDATED ON THE SAME EDGE OF WHEN SRAM ACCEPTS A REQUEST, SO IT WORKS
                case (req_type)
                    READ_BYTE: begin 
                        sram_addr <= req_addr;
                        sram_read <= 1'b1;
                        state <= READ_WAIT;
                    end
                    WRITE_BYTE: begin 
                        sram_din  <= req_wdata[7:0];
                        sram_addr <= req_addr; 
                        state <= WRITE;
                        sram_str <= 1'b1;
                    end
                    WRITE_WORD: begin
                        sram_str <= 1'b1;
                        state <= WRITE;
                        //write first thingy;
                        byte_sel <= 1'b1;
                        sram_addr <= req_addr;
                        sram_din <= req_wdata[7:0];
                    end
                    READ_WORD: begin
                        sram_read  <= 1'b1;   
                        sram_addr  <= req_addr; //requests the first byte
                        byte_sel_d <= 1'b0; //set to 0, so that the low byte can be used
                        state <= READ_WAIT;
                    end                    
                endcase
                end  
            end
            RESP_WAIT:begin
                if (resp_done) begin
                    out_rdy <= 1'b0;
                    req_rdy <= 1'b1;
                    state   <= IDLE;
                end
            end
            default: state <= IDLE;
        endcase
    end
end
endmodule