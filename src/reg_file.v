module reg_file #(
    parameter DATA_WIDTH = 16,
    parameter NUM_REGS   = 16
)(
    input                       clk,
    input                       reset,
    input  [3:0]                A1, A2, A3,
    output [DATA_WIDTH-1:0]     RS1,
    output [DATA_WIDTH-1:0]     RS2,
    input  [DATA_WIDTH-1:0]     block_idx,
    input  [DATA_WIDTH-1:0]     block_dim,
    input  [DATA_WIDTH-1:0]     thread_idx,
    input  [DATA_WIDTH-1:0]     WD,
    input                       we,
    input                       reg_en
);
    reg [DATA_WIDTH-1:0] REGISTER [0:NUM_REGS-1];
    integer i;

    // Forwarding: remember last write
    reg [3:0]               last_write_addr;
    reg [DATA_WIDTH-1:0]    last_write_data;
    reg                     last_write_valid;

    // Read function with forwarding
    function [DATA_WIDTH-1:0] rd_reg;
        input [3:0] a;
        begin
            if (last_write_valid && a == last_write_addr)
                rd_reg = last_write_data;
            else begin
                case (a)
                    4'd0:    rd_reg = {DATA_WIDTH{1'b0}};
                    4'd13:   rd_reg = block_idx;
                    4'd14:   rd_reg = block_dim;
                    4'd15:   rd_reg = thread_idx;
                    default: rd_reg = REGISTER[a];
                endcase
            end
        end
    endfunction

    assign RS1 = rd_reg(A1);
    assign RS2 = rd_reg(A2);

    always @(posedge clk) begin
        if (reset) begin
            last_write_valid <= 1'b0;
            for (i = 0; i < NUM_REGS; i = i + 1)
                REGISTER[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            // Update REGISTER array normally (NBA)
            if (we && A3 != 4'd0 && A3 != 4'd13 && A3 != 4'd14 && A3 != 4'd15)
                REGISTER[A3] <= WD;

            // Capture last write for forwarding (same conditions)
            if (we && A3 != 4'd0 && A3 != 4'd13 && A3 != 4'd14 && A3 != 4'd15) begin
                last_write_addr  <= A3;
                last_write_data  <= WD;
                last_write_valid <= 1'b1;
            end else begin
                // Invalidate after one cycle (forward only the immediately preceding write)
                last_write_valid <= 1'b0;
            end
        end
    end
endmodule