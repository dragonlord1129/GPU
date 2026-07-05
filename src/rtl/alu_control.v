module alu_control(
    input [3:0] opcode,
    output reg [3:0] ALUControl
);

always @(*) begin

    case(opcode)

        4'h0: ALUControl = 4'b0000; // ADD
        4'h1: ALUControl = 4'b0001; // SUB
        4'h2: ALUControl = 4'b0010; // AND
        4'h3: ALUControl = 4'b0011; // OR
        4'h4: ALUControl = 4'b0100; // XOR
        4'h5: ALUControl = 4'b0101; // MUL_Lower
        4'h6: ALUControl = 4'b0110; // MUL_Higher
        4'h7: ALUControl = 4'b0111; // DIV_Q
        4'h8: ALUControl = 4'b1000; // DIV_R
        4'h9: ALUControl = 4'b1001; // SLT

        4'hA: ALUControl = 4'b1010; // LW addr calc
        4'hB: ALUControl = 4'b1011; // SW addr calc

        4'hC: ALUControl = 4'b1100; // BEQ compare

        default:
            ALUControl = 4'b0000;

    endcase

end

endmodule