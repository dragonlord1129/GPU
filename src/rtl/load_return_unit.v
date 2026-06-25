module load_return_unit(
    input lw_ready,

    input [15:0] load_data,
    input [3:0] destination_reg,

    output reg reg_write,
    output reg [3:0] rd,
    output reg [15:0] wb_data
);

always @(*) begin

    reg_write = lw_ready;
    rd        = destination_reg;
    wb_data   = load_data;

end

endmodule