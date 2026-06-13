module reg_file #(
    parameter DATA_WIDTH = 16,
    parameter NUM_REGS   = 16
)(
    input                       clk,
    input                       reset,
    input  [3:0]                A1, A2, A3,
    output [DATA_WIDTH-1:0]      RS1,
    output [DATA_WIDTH-1:0]      RS2,
    input  [DATA_WIDTH-1:0]      block_idx,
    input  [DATA_WIDTH-1:0]      block_dim,
    input  [DATA_WIDTH-1:0]      thread_idx,
    input  [DATA_WIDTH-1:0]      WD,
    input                       we,
    input                       reg_en      // accepted for interface compatibility
);
    reg [DATA_WIDTH-1:0] REGISTER [0:NUM_REGS-1];
    integer i;
 
    function [DATA_WIDTH-1:0] rd_reg;
        input [3:0] a;
        begin
            case (a)
                4'd0:    rd_reg = {DATA_WIDTH{1'b0}};
                4'd13:   rd_reg = block_idx;
                4'd14:   rd_reg = block_dim;
                4'd15:   rd_reg = thread_idx;
                default: rd_reg = REGISTER[a];
            endcase
        end
    endfunction
 
    assign RS1 = rd_reg(A1);
    assign RS2 = rd_reg(A2);
 
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < NUM_REGS; i = i + 1)
                REGISTER[i] <= {DATA_WIDTH{1'b0}};
        end else if (we) begin
            // protect x0 and the read-only special registers
            if (A3 != 4'd0 && A3 != 4'd13 && A3 != 4'd14 && A3 != 4'd15)
                REGISTER[A3] <= WD;
        end
    end
endmodule