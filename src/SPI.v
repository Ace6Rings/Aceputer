`default_nettype none
module QSPI (
    input  wire               clk, //prolly not needed since its the same clock anyway and the clock speed is slow
    input  wire  [3:0]       MOSI,
    input  wire                CS,   
    input  wire               ack,  //1 = cpu took the instruction, 0 = it didn't
    input  wire           req_out,  // from cpu, if 1, then the cpu wants to talk
    input  wire [15:0]    req_dat,

    output reg           dat_sent,
    output reg  [3:0]        MISO, 
    output reg  [15:0]   word_out,
    output reg           word_valid,
);

reg [15:0] word_out; 
reg [15:0] shift_reg;
reg [15:0] req_dat_reg;

reg word_valid; 
reg [1:0] RX_counter; //2 bit counter
reg [1:0] TX_counter; 
reg       TX_FLAG; //used to put the value from req_dat to req_dat_reg
initial RX_counter = 2'b00;
initial TX_counter = 2'b00;

always @ (posedge clk) begin
    if (ack) begin
        word_valid <= 1'b0;
        RX_counter <= 1'b0;
        dat_sent <= 1'b0;
    end
    if (CS) begin //cs is active LOW
        RX_counter <= 2'd0;
    end
    else if (!word_valid) begin
        shift_reg  <= {shift_reg[11:0], MOSI};
        RX_counter <= RX_counter + 2'b01;

        if (RX_counter == 2'b11) begin
            word_out   <= {shift_reg[11:0], MOSI};
            word_valid <= 1'b1;
        end
    end
    if (req_out && !TX_FLAG && !dat_sent)begin
        req_dat_reg <= req_dat;
        TX_FLAG <= 1'b1;
    end
    if (req_out && !CS && TX_FLAG) begin
        if (TX_counter != 2'b11) begin
            MISO <= req_dat_reg [15:12]; //sends the 4 most significant bit
            req_dat_reg <= req_dat_reg << 4; //shift right 4
            TX_counter  <= TX_counter + 2'b01;
        end
        else if (TX_counter == 2'b11) begin
            dat_sent <= 1'b1;
        end
    end
end
endmodule
    
