module data_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 12              // 4096 words
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
begin
    if(writeEnable)
        memory[A] <= writeData;
end
// ----------------------------------------------------------------
// Test preload – hardcoded Matrix A and B for matrix‑add test.
// Remove or comment out for other tests.
// ----------------------------------------------------------------
integer init_idx;
initial begin
    for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1)
        memory[init_idx] = 0;

    // Matrix A: addresses 0..15  = 1,2,3,...16
    memory[0]  = 16'd1;   memory[1]  = 16'd2;   memory[2]  = 16'd3;   memory[3]  = 16'd4;
    memory[4]  = 16'd5;   memory[5]  = 16'd6;   memory[6]  = 16'd7;   memory[7]  = 16'd8;
    memory[8]  = 16'd9;   memory[9]  = 16'd10;  memory[10] = 16'd11;  memory[11] = 16'd12;
    memory[12] = 16'd13;  memory[13] = 16'd14;  memory[14] = 16'd15;  memory[15] = 16'd16;

    // Matrix B: addresses 16..31 = 10,20,30,...160
    memory[16] = 16'd10;  memory[17] = 16'd20;  memory[18] = 16'd30;  memory[19] = 16'd40;
    memory[20] = 16'd50;  memory[21] = 16'd60;  memory[22] = 16'd70;  memory[23] = 16'd80;
    memory[24] = 16'd90;  memory[25] = 16'd100; memory[26] = 16'd110; memory[27] = 16'd120;
    memory[28] = 16'd130; memory[29] = 16'd140; memory[30] = 16'd150; memory[31] = 16'd160;
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