module main_control(
    input [3:0] opcode,

    output reg RegWrite,
    output reg MemRead,
    output reg MemWrite,
    output reg Branch,
    output reg Jump,
    output reg Halt,
    output reg ALUSrc
);

always @(*) begin

    RegWrite = 0;
    MemRead  = 0;
    MemWrite = 0;
    Branch   = 0;
    Jump     = 0;
    Halt     = 0;
    ALUSrc   = 0;

    case(opcode)

        4'h0,
        4'h1,
        4'h2,
        4'h3,
        4'h4,
        4'h5:
            RegWrite = 1;

        4'h6: begin
            RegWrite = 1;
            MemRead  = 1;
            ALUSrc   = 1;
        end

        4'h7: begin
            MemWrite = 1;
            ALUSrc   = 1;
        end

        4'h8:
            Branch = 1;

        4'h9:
            Jump = 1;

        4'hA:
            Halt = 1;

    endcase

end

endmodule