`ifndef defines_vh
`define defines_vh

// OPCODES


`define OP_NOP   4'h0

`define OP_ADD   4'h1
`define OP_SUB   4'h2
`define OP_ADDI  4'h3  //can be used for subtraction

`define OP_STORE 4'h4
`define OP_LOAD  4'h5  //store and load to/from sram

`define OP_SHL   4'h6
`define OP_SHR   4'h7

`define OP_LDI   4'h8
`define OP_LDB   4'h9
`define OP_MOV   4'hA

`define MUL      4'hB
`define OP_OUT   4'hC

`define OP_JZ    4'hD
`define OP_JNZ   4'hE
`define OP_HALT  4'hF

`endif

