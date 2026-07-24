module data_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 12
)(
    input                         clk,
    input  [ADDR_WIDTH-1:0]       A,
    input  [DATA_WIDTH-1:0]       writeData,
    input                         writeEnable,
    output [DATA_WIDTH-1:0]       RD
);
    localparam DEPTH = (1 << ADDR_WIDTH);
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    assign RD = memory[A];

    always @(posedge clk)
        if (writeEnable) memory[A] <= writeData;

    integer init_idx;
    initial begin
        for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1)
            memory[init_idx] = 0;
            memory[ 0] = 1;  memory[ 1] = 2;  memory[ 2] = 3;  memory[ 3] = 4;
            memory[ 4] = 5;  memory[ 5] = 6;  memory[ 6] = 7;  memory[ 7] = 8;
            memory[ 8] = 9;  memory[ 9] =10;  memory[10] =11;  memory[11] =12;
            memory[12] =13;  memory[13] =14;  memory[14] =15;  memory[15] =16;

            // ---- Matrix B (4x4 identity) ----
            memory[16] = 1;  memory[17] = 0;  memory[18] = 0;  memory[19] = 0;
            memory[20] = 0;  memory[21] = 1;  memory[22] = 0;  memory[23] = 0;
            memory[24] = 0;  memory[25] = 0;  memory[26] = 1;  memory[27] = 0;
            memory[28] = 0;  memory[29] = 0;  memory[30] = 0;  memory[31] = 1;
         // ========== Stress‑test constant tables ==========
            // Warp 0
            memory[16'h400] = 16'h0000;  memory[16'h401] = 16'h0100;
            memory[16'h402] = 16'h0200;  memory[16'h403] = 16'h0300;
            memory[16'h404] = 16'd0;     memory[16'h405] = 16'd16;
            memory[16'h406] = 16'd32;    memory[16'h407] = 16'd48;
            // Warp 1
            memory[16'h408] = 16'h0400;  memory[16'h409] = 16'h0500;
            memory[16'h40A] = 16'h0600;  memory[16'h40B] = 16'h0700;
            memory[16'h40C] = 16'd0;     memory[16'h40D] = 16'd16;
            memory[16'h40E] = 16'd32;    memory[16'h40F] = 16'd48;
            // Warp 2
            memory[16'h410] = 16'h0800;  memory[16'h411] = 16'h0900;
            memory[16'h412] = 16'h0A00;  memory[16'h413] = 16'h0B00;
            memory[16'h414] = 16'd0;     memory[16'h415] = 16'd16;
            memory[16'h416] = 16'd32;    memory[16'h417] = 16'd48;
            // Warp 3
            memory[16'h418] = 16'h0C00;  memory[16'h419] = 16'h0D00;
            memory[16'h41A] = 16'h0E00;  memory[16'h41B] = 16'h0F00;
            memory[16'h41C] = 16'd0;     memory[16'h41D] = 16'd16;
            memory[16'h41E] = 16'd32;    memory[16'h41F] = 16'd48;
        // memory[0] = 5;
        // memory[1] = 7;
        // memory[2] = 0;        // store target
        // memory[4095] = 0; // dummy slow load target
    end
endmodule

module data_memory_line #(

    parameter DATA_WIDTH = 32,
    parameter LINE_WORDS = 16,
    parameter OFFSET_BITS = 4,
    parameter ADDR_WIDTH = 12

)(
    input clk,
    input mem_write,
    input [ADDR_WIDTH-OFFSET_BITS-1:0] addr_base,
    input [LINE_WORDS-1:0] sw_word_mask,
    input [DATA_WIDTH-1:0] sw_line_out [0:LINE_WORDS-1],

    output [DATA_WIDTH-1:0] lw_line_in [0:LINE_WORDS-1]
);

    generate

    genvar i;

    for(i=0;i<LINE_WORDS;i=i+1)
        begin : gen_mem_line
            data_memory #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH)
            )
            mem
            (
                .clk(clk),
                .A({addr_base,i[OFFSET_BITS-1:0]}),
                .writeData(sw_line_out[i]),
                .writeEnable(mem_write & sw_word_mask[i]),
                .RD(lw_line_in[i])
            );
        end
    endgenerate
endmodule