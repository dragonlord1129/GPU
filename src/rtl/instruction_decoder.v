module instruction_decoder(
    input [31:0] instruction,

    output [3:0] opcode,
    output [3:0] rd,
    output [3:0] rs1,
    output [3:0] rs2,
    output [15:0] imm
);

assign opcode = instruction[31:28];
assign rd     = instruction[27:24];
assign rs1    = instruction[23:20];
assign rs2    = instruction[19:16];
assign imm    = instruction[15:0];

endmodule