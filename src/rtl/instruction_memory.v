module instruction_memory (
    input  [15:0] A,             // 16‑bit PC
    output [31:0] RD
);
    reg [31:0] memory [0:32767]; // depth 32768, index 15 bits
    assign RD = memory[A[14:0]]; // use lower 15 bits to avoid wrap
    initial $readmemh("memfile.hex", memory);
endmodule