// ============================
// Instruction Memory Module
// ============================
module instruction_memory (
    input [7:0] A,              // Address to fetch instruction
    output [31:0] RD             // Instruction read
);
    reg [31:0] memory [255:0]; // Instruction memory array

    assign RD = memory[A];

    initial begin
        $readmemh("memfile.hex", memory); // Load instructions from file
    end
endmodule