module writeback_mux(
    input [15:0] alu_result,
    input [15:0] mem_result,
    input MemRead,

    output [15:0] wb_data
);

assign wb_data =
        MemRead ?
        mem_result :
        alu_result;

endmodule