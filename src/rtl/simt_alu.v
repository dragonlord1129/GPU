module simt_alu #(
    parameter LANES = 16,
    parameter WIDTH = 16
)(
    input [WIDTH-1:0] A [0:LANES-1],
    input [WIDTH-1:0] B [0:LANES-1],

    input [3:0] ALUControl,

    output [WIDTH-1:0] Result [0:LANES-1]
);

genvar i;


generate
    for(i=0;i<LANES;i=i+1)
    begin : ALUS

        alu #(
            .WIDTH(WIDTH)
        )
        lane_alu(
            .A(A[i]),
            .B(B[i]),
            .ALUControl(ALUControl),

            .result(Result[i]),

            .carry(),
            .zero(),
            .overflow(),
            .negative(),
            .divide_by_zero()
        );

    end
endgenerate

endmodule