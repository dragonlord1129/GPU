module main_decoder(
    input  [3:0] opcode,

    output reg RegWrite,
    output reg MemRead,
    output reg MemWrite,
    output reg ALUSrc,
    output reg Branch,
    output reg Jump,
    output reg Halt,

    output reg [3:0] ALUControl,
    output reg [1:0] ResultSrc
);

always @(*) begin

    RegWrite  = 0;
    MemRead   = 0;
    MemWrite  = 0;
    ALUSrc    = 0;
    Branch    = 0;
    Jump      = 0;
    Halt      = 0;

    ALUControl = 4'b0000;
    ResultSrc  = 2'b00;

    case(opcode)

        4'h0: begin           // ADD
            RegWrite  = 1;
            ALUControl = 4'b0000;
        end

        4'h1: begin           // SUB
            RegWrite  = 1;
            ALUControl = 4'b0001;
        end

        4'h2: begin           // AND
            RegWrite  = 1;
            ALUControl = 4'b0010;
        end

        4'h3: begin           // OR
            RegWrite  = 1;
            ALUControl = 4'b0011;
        end

        4'h4: begin           // XOR
            RegWrite  = 1;
            ALUControl = 4'b0100;
        end

        4'h5: begin           // MUL
            RegWrite  = 1;
            ALUControl = 4'b0101;
        end

        4'h6: begin           // LW
            RegWrite  = 1;
            MemRead   = 1;
            ALUSrc    = 1;
            ALUControl = 4'b0000;
            ResultSrc  = 2'b01;
        end

        4'h7: begin           // SW
            MemWrite  = 1;
            ALUSrc    = 1;
            ALUControl = 4'b0000;
        end

        4'h8: begin           // BEQ
            Branch    = 1;
            ALUControl = 4'b0001;
        end

        4'h9: begin           // JUMP
            Jump = 1;
        end

        4'hA: begin           // HALT
            Halt = 1;
        end

        default: begin
        end

    endcase

end

endmodule