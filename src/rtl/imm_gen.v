module imm_gen #(parameter DATA_WIDTH = 32)(
    input  [15:0]            imm,
    output [DATA_WIDTH-1:0]  imm_out
);
    // zero-extend 16-bit immediate to DATA_WIDTH
    assign imm_out = {{(DATA_WIDTH-16){1'b0}}, imm};

endmodule