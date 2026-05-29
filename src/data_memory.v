module data_memory #(
    parameter ADDR_WIDTH = 8,
    parameter DEPTH = 256
)(
    input [ADDR_WIDTH-1:0] A,
    input [31:0] writeData,
    input clk,
    input writeEnable,
    output [31:0] RD
);

reg [31:0] data_memory [0:DEPTH-1];

// asynchronous read
assign RD = data_memory[A];

integer i;

always @(posedge clk) begin
    if (writeEnable)
        data_memory[A] <= writeData;
end

initial begin
    for (i = 0; i < DEPTH; i = i + 1)
        data_memory[i] = 32'b0;
end

endmodule