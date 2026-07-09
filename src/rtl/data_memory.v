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
        // Zero all memory
        for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1)
            memory[init_idx] = 0;

        // Matrix A (0..15) = 1..16
        memory[0]  = 1;   memory[1]  = 2;   memory[2]  = 3;   memory[3]  = 4;
        memory[4]  = 5;   memory[5]  = 6;   memory[6]  = 7;   memory[7]  = 8;
        memory[8]  = 9;   memory[9]  = 10;  memory[10] = 11;  memory[11] = 12;
        memory[12] = 13;  memory[13] = 14;  memory[14] = 15;  memory[15] = 16;

        // Matrix B (16..31) = ALL ONES
        memory[16] = 1;   memory[17] = 0;   memory[18] = 0;   memory[19] = 0;
        memory[20] = 0;   memory[21] = 1;   memory[22] = 0;   memory[23] = 0;
        memory[24] = 0;   memory[25] = 0;   memory[26] = 1;   memory[27] = 0;
        memory[28] = 0;   memory[29] = 0;   memory[30] = 0;   memory[31] = 1;

        // Row indices (100..115): 0,0,0,0, 1,1,1,1, 2,2,2,2, 3,3,3,3
        memory[100]=0; memory[101]=0; memory[102]=0; memory[103]=0;
        memory[104]=1; memory[105]=1; memory[106]=1; memory[107]=1;
        memory[108]=2; memory[109]=2; memory[110]=2; memory[111]=2;
        memory[112]=3; memory[113]=3; memory[114]=3; memory[115]=3;

        // Column indices (116..131) = 0,1,2,3 repeating
        for (init_idx = 0; init_idx < 16; init_idx = init_idx + 1)
            memory[116 + init_idx] = init_idx % 4;

        // Constant 32 at address 200
        memory[200] = 32;
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