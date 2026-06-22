`timescale 1ns/1ps

module tb_main_decoder;

reg [3:0] opcode;

wire RegWrite;
wire MemRead;
wire MemWrite;
wire ALUSrc;
wire Branch;
wire Jump;
wire Halt;

wire [3:0] ALUControl;
wire [1:0] ResultSrc;

main_decoder dut(
    .opcode(opcode),

    .RegWrite(RegWrite),
    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .ALUSrc(ALUSrc),
    .Branch(Branch),
    .Jump(Jump),
    .Halt(Halt),

    .ALUControl(ALUControl),
    .ResultSrc(ResultSrc)
);

initial begin

    //------------------------------------------------
    // ADD
    //------------------------------------------------

    opcode = 4'h0;
    #1;

    if(!RegWrite || ALUControl != 4'b0000) begin
        $display("ADD FAIL");
        $finish;
    end

    //------------------------------------------------
    // SUB
    //------------------------------------------------

    opcode = 4'h1;
    #1;

    if(!RegWrite || ALUControl != 4'b0001) begin
        $display("SUB FAIL");
        $finish;
    end

    //------------------------------------------------
    // AND
    //------------------------------------------------

    opcode = 4'h2;
    #1;

    if(!RegWrite || ALUControl != 4'b0010) begin
        $display("AND FAIL");
        $finish;
    end

    //------------------------------------------------
    // OR
    //------------------------------------------------

    opcode = 4'h3;
    #1;

    if(!RegWrite || ALUControl != 4'b0011) begin
        $display("OR FAIL");
        $finish;
    end

    //------------------------------------------------
    // XOR
    //------------------------------------------------

    opcode = 4'h4;
    #1;

    if(!RegWrite || ALUControl != 4'b0100) begin
        $display("XOR FAIL");
        $finish;
    end

    //------------------------------------------------
    // MUL
    //------------------------------------------------

    opcode = 4'h5;
    #1;

    if(!RegWrite || ALUControl != 4'b0101) begin
        $display("MUL FAIL");
        $finish;
    end

    //------------------------------------------------
    // LW
    //------------------------------------------------

    opcode = 4'h6;
    #1;

    if(!RegWrite || !MemRead || !ALUSrc ||
       ResultSrc != 2'b01) begin

        $display("LW FAIL");
        $finish;
    end

    //------------------------------------------------
    // SW
    //------------------------------------------------

    opcode = 4'h7;
    #1;

    if(!MemWrite || !ALUSrc) begin
        $display("SW FAIL");
        $finish;
    end

    //------------------------------------------------
    // BEQ
    //------------------------------------------------

    opcode = 4'h8;
    #1;

    if(!Branch || ALUControl != 4'b0001) begin
        $display("BEQ FAIL");
        $finish;
    end

    //------------------------------------------------
    // JUMP
    //------------------------------------------------

    opcode = 4'h9;
    #1;

    if(!Jump) begin
        $display("JUMP FAIL");
        $finish;
    end

    //------------------------------------------------
    // HALT
    //------------------------------------------------

    opcode = 4'hA;
    #1;

    if(!Halt) begin
        $display("HALT FAIL");
        $finish;
    end

    $display("");
    $display("========================");
    $display("DECODER TEST PASSED");
    $display("========================");
    $display("");

    $finish;

end

endmodule