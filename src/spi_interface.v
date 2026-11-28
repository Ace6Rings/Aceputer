/*
 * Copyright (c) 2026 Steven Xie
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none
module QSPI (
    input  wire             rst_n,
    input  wire               clk, //prolly not needed since its the same clock anyway and the clock speed is slow
    input  wire  [3:0]       MOSI,
    input  wire                CS,   
    input  wire               ack,  //1 = cpu took the instruction, 0 = it didn't
    input  wire           req_out,  // from cpu, if 1, then the cpu wants to talk
    input  wire [15:0]    req_dat,

    output reg           dat_sent,
    output reg  [3:0]        MISO, 
    output reg  [15:0]   word_out,
    output reg           word_valid
);


reg [15:0] shift_reg;
reg [15:0] req_dat_reg;

reg [1:0] RX_counter; //2 bit counter
reg [1:0] TX_counter; 
reg       TX_FLAG; //used to put the value from req_dat to req_dat_reg


always @ (posedge clk) begin
    if (!rst_n) begin
        word_out    <= 16'h0000;
        shift_reg   <= 16'h0000;
        req_dat_reg <= 16'h0000;
        word_valid  <= 1'b0;
        dat_sent    <= 1'b0;
        MISO        <= 4'b0000;
        RX_counter  <= 2'b00;
        TX_counter  <= 2'b00;
        TX_FLAG     <= 1'b0;
    end
    else begin 
        if (ack) begin
        word_valid <= 1'b0;
    end
    if (CS) begin //cs is active LOW
        RX_counter <= 2'd0;
    end
    else if (!word_valid && !req_out) begin
        shift_reg  <= {shift_reg[11:0], MOSI};
        RX_counter <= RX_counter + 2'b01;

        if (RX_counter == 2'b11) begin
            word_out   <= {shift_reg[11:0], MOSI};
            word_valid <= 1'b1;
        end
    end
    if (!req_out) begin
        TX_counter <= 2'b00;
        TX_FLAG    <= 1'b0;
        dat_sent   <= 1'b0;
    end
    else if (!TX_FLAG && !dat_sent) begin
        req_dat_reg <= req_dat; 
        TX_FLAG <= 1'b1;
        TX_counter <= 2'b00;
    end
    else if (!CS && TX_FLAG) begin
        MISO <= req_dat_reg[15:12];
        if (TX_counter != 2'b11) begin
            req_dat_reg <= req_dat_reg << 4;
            TX_counter  <= TX_counter + 2'b01;
        end else begin
            TX_FLAG    <= 1'b0;
            TX_counter <= 2'b00;
            dat_sent   <= 1'b1;
        end
    end
    end
end
endmodule
    


