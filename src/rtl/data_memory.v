// ============================================================================
//  data_memory  -- exactly the module supplied by the user (word-wide, 1 port,
//                   async read, sync write).
// ============================================================================
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
assign RD = data_memory[A];

integer i;

always @(posedge clk) begin
    if (writeEnable)
        data_memory[A] <= writeData;
end


endmodule


module data_memory_line #(
    parameter LINE_WORDS  = 16,
    parameter OFFSET_BITS = 4,
    parameter INDEX_BITS  = 8           // number of lines = 2**INDEX_BITS
) (
    input                    clk,
    input                    mem_write,
    input  [15:0]            addr_base,                  // block BASE address
    input  [LINE_WORDS-1:0]  sw_word_mask,
    input  [15:0]            sw_line_out [0:LINE_WORDS-1],
    output [15:0]            lw_line_in  [0:LINE_WORDS-1]
);

    wire [INDEX_BITS-1:0] line_index = addr_base[OFFSET_BITS +: INDEX_BITS];

    genvar k;
    generate
        for (k = 0; k < LINE_WORDS; k = k + 1) begin : bank
            wire [31:0] rd_word;
            data_memory #(
                .ADDR_WIDTH (INDEX_BITS),
                .DEPTH      (1 << INDEX_BITS)
            ) u_bank (
                .A          (line_index),
                .writeData  ({16'b0, sw_line_out[k]}),
                .clk        (clk),
                .writeEnable(mem_write & sw_word_mask[k]),
                .RD         (rd_word)
            );
            assign lw_line_in[k] = rd_word[15:0];
        end
    endgenerate

endmodule