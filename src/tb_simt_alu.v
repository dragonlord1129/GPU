`timescale 1ns/1ps

module tb_simt_alu;

parameter LANES = 16;
parameter WIDTH = 16;

reg  [WIDTH-1:0] A [0:LANES-1];
reg  [WIDTH-1:0] B [0:LANES-1];

reg  [3:0] ALUControl;

wire [WIDTH-1:0] Result [0:LANES-1];

//////////////////////////////////////////////////////
// DUT
//////////////////////////////////////////////////////

simt_alu #(
    .LANES(LANES),
    .WIDTH(WIDTH)
)
dut (
    .A(A),
    .B(B),
    .ALUControl(ALUControl),
    .Result(Result)
);

integer i;

//////////////////////////////////////////////////////
// Initialize Inputs
//////////////////////////////////////////////////////

initial begin

    for(i=0;i<LANES;i=i+1) begin
        A[i] = i + 10;
        B[i] = i + 1;
    end

    //////////////////////////////////////////////////
    // ADD
    //////////////////////////////////////////////////

    ALUControl = 4'b0000;

    #10;

    $display("\n=== ADD TEST ===");

    for(i=0;i<LANES;i=i+1) begin
        $display(
            "Lane %0d : %0d + %0d = %0d",
            i,
            A[i],
            B[i],
            Result[i]
        );

        if(Result[i] !== (A[i] + B[i])) begin
            $display("FAIL ADD lane %0d",i);
            $finish;
        end
    end

    //////////////////////////////////////////////////
    // SUB
    //////////////////////////////////////////////////

    ALUControl = 4'b0001;

    #10;

    $display("\n=== SUB TEST ===");

    for(i=0;i<LANES;i=i+1) begin

        if(Result[i] !== (A[i] - B[i])) begin
            $display("FAIL SUB lane %0d",i);
            $finish;
        end

    end

    $display("SUB PASS");

    //////////////////////////////////////////////////
    // AND
    //////////////////////////////////////////////////

    ALUControl = 4'b0010;

    #10;

    for(i=0;i<LANES;i=i+1) begin

        if(Result[i] !== (A[i] & B[i])) begin
            $display("FAIL AND lane %0d",i);
            $finish;
        end

    end

    $display("AND PASS");

    //////////////////////////////////////////////////
    // OR
    //////////////////////////////////////////////////

    ALUControl = 4'b0011;

    #10;

    for(i=0;i<LANES;i=i+1) begin

        if(Result[i] !== (A[i] | B[i])) begin
            $display("FAIL OR lane %0d",i);
            $finish;
        end

    end

    $display("OR PASS");

    //////////////////////////////////////////////////
    // XOR
    //////////////////////////////////////////////////

    ALUControl = 4'b0100;

    #10;

    for(i=0;i<LANES;i=i+1) begin

        if(Result[i] !== (A[i] ^ B[i])) begin
            $display("FAIL XOR lane %0d",i);
            $finish;
        end

    end

    $display("XOR PASS");

    //////////////////////////////////////////////////
    // MUL
    //////////////////////////////////////////////////

    ALUControl = 4'b0101;

    #20;

    for(i=0;i<LANES;i=i+1) begin

        if(Result[i] !== ((A[i] * B[i]) & 16'hFFFF)) begin
            $display(
                "FAIL MUL lane %0d expected=%0d got=%0d",
                i,
                (A[i]*B[i]),
                Result[i]
            );
            $finish;
        end

    end

    $display("MUL PASS");

    //////////////////////////////////////////////////
    // Complete
    //////////////////////////////////////////////////

    $display("\n========================");
    $display("SIMT ALU TEST PASSED");
    $display("========================");

    $finish;

end

endmodule