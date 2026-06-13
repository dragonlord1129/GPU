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


// ============================================================================
//  data_memory_line
// ----------------------------------------------------------------------------
//  A block / cache-line view built ON TOP of the user's word-wide data_memory,
//  honouring the WIDENED contract the coalescing memory_scheduler expects:
//
//      * a line = LINE_WORDS consecutive words, aligned on LINE_WORDS
//      * one transaction moves the WHOLE line in a single cycle
//      * line base address has its low OFFSET_BITS cleared; word k = base + k
//
//  Implementation: LINE_WORDS independent banks of the ORIGINAL data_memory.
//  Bank k stores word k of every line, addressed by the line index
//  ( = addr_base >> OFFSET_BITS ). Because data_memory reads asynchronously,
//  all LINE_WORDS words appear combinationally -> the scheduler's 1-cycle
//  latency contract holds. A per-word store mask drives a per-bank
//  writeEnable, so only masked words are written and the rest are untouched
//  (no read-modify-write needed -- words live in separate banks).
//
//  The schedulers use 16-bit words; the user's memory is 32 bits wide, so the
//  low 16 bits of each bank are used.
// ============================================================================
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