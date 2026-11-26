module gf180mcu_ocd_ip_sram__sram256x8m8wm1 (
    input  wire       CLK,
    input  wire [7:0] A,
    input  wire [7:0] D,
    output reg  [7:0] Q,
    input  wire       CEN,
    input  wire       GWEN,
    input  wire [7:0] WEN
);
    reg [7:0] mem [0:255];

    always @(posedge CLK) begin
        if (!CEN) begin
            if (!GWEN) mem[A] <= D;
            else       Q <= mem[A];
        end
    end
endmodule

//for fpga to work right hopefully