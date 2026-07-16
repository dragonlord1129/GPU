module instruction_memory #(
    parameter MEMFILE = "memfile.hex"   // path to hex memory image
)(
    input  [15:0] A,
    output [31:0] RD
    // output reg    mem_ready = 1'b0       // goes high only after load completes
);
    reg [31:0] memory [0:32767];
    integer idx;

    initial begin
        
        for (idx = 0; idx < 32768; idx = idx + 1)
            memory[idx] = 32'hA0000000;

        $readmemh(MEMFILE, memory);

    end

    assign RD = memory[A[14:0]];
endmodule