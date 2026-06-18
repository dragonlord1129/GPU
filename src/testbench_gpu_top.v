// ============================================================
// testbench.v -- self-checking, uses memfile.hex
// ============================================================
`timescale 1ns / 1ps
module testbench_gpu_top;
    reg         clk, reset;
    reg  [3:0]  lane_select;
    wire [15:0] debug_pc;
    wire [15:0] debug_regs [0:3][0:15][0:15];
    wire [15:0] debug_lw_out, debug_alu_result;
    wire        done;

    integer cycle_cnt;

    gpu_top #(.NUMBER_OF_WARPS(4), .NUMBER_OF_THREADS(16), .DATA_WIDTH(16)) dut (
        .clk(clk), .reset(reset), .lane_select(lane_select),
        .debug_pc(debug_pc), .debug_regs(debug_regs),
        .debug_lw_out(debug_lw_out), .debug_alu_result(debug_alu_result),
        .done(done)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        lane_select = 0;
        cycle_cnt = 0;

        #15 reset = 0;

        while (!done && cycle_cnt < 5000) begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;
        end

        if (done) begin
            $display("SUCCESS: GPU completed execution in %0d cycles", cycle_cnt);
        end else begin
            $display("FAIL: Timeout after %0d cycles", cycle_cnt);
        end

        $finish;
    end

    // Optional: print PC and instruction each cycle
    always @(posedge clk) begin
        if (dut.running && dut.warp_ready_mask[0])
            $display("Cycle %0d: PC = %h, Instr = %h", cycle_cnt, debug_pc, dut.instr);
    end
endmodule