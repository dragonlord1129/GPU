module imm_gen #(parameter DATA_WIDTH = 16)(
    input  [15:0]            imm,
    output [DATA_WIDTH-1:0]  imm_out
);
    assign imm_out = imm[DATA_WIDTH-1:0];
endmodule