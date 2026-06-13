`timescale 1ns/1ps
// ============================================================================
//  tb_gpu_top -- drives gpu_top running memfile.hex (the loop kernel), checks
//  every lane's result, counts coalesced memory transactions, measures memory
//  latency, and dumps the resulting data memory.
//
//  Kernel (same program for all 4 warps; blockIdx = warp id selects the data):
//     r4 = MEM[gi] where the stored value = 3*gi + 0x100,  gi = warp*16 + lane
// ============================================================================
module tb_gpu_top;
    reg clk = 0, reset;
    reg [3:0] lane_select = 0;
    wire [15:0] debug_pc, debug_lw_out, debug_alu_result;
    wire [15:0] debug_regs [0:3][0:15][0:15];
    wire done;

    always #5 clk = ~clk;

    gpu_top dut (
        .clk(clk), .reset(reset), .lane_select(lane_select),
        .debug_pc(debug_pc), .debug_regs(debug_regs),
        .debug_lw_out(debug_lw_out), .debug_alu_result(debug_alu_result),
        .done(done)
    );

    integer cyc = 0;
    always @(posedge clk) if (!reset) cyc = cyc + 1;

    reg [2:0] prev_ms_state;
    integer transactions = 0;
    integer mem_busy_cycles = 0;
    integer first_req_cyc = -1, first_done_cyc = -1;
    localparam [2:0] WAIT = 3'b100;

    always @(posedge clk) if (!reset) begin
        if (dut.scheduler_inst.state_curr != 3'b000) mem_busy_cycles = mem_busy_cycles + 1;
        if (dut.scheduler_inst.state_curr == WAIT && prev_ms_state != WAIT)
            transactions = transactions + 1;
        if (dut.mem_req && first_req_cyc < 0)  first_req_cyc  = cyc;
        if (dut.mem_done && first_done_cyc < 0) first_done_cyc = cyc;
        prev_ms_state = dut.scheduler_inst.state_curr;
    end

    integer w, i, errors, exp;
    initial begin
        reset = 1;
        repeat (4) @(negedge clk);
        reset = 0;

        fork : run
            begin wait (done == 1'b1); disable run; end
            begin repeat (4000) @(negedge clk);
                  $display("TIMEOUT"); disable run; end
        join
        @(negedge clk);

        $display("\n================= RUN SUMMARY =================");
        $display(" finished (done=%b) at cycle %0d", done, cyc);
        $display(" memory FSM busy ............ %0d cycles", mem_busy_cycles);
        $display(" coalesced block transactions %0d  (4 warps x [1 store +1 load] = 8 if fully coalesced)", transactions);
        $display(" first memory op latency .... %0d cycles (mem_req @%0d -> mem_done @%0d)",
                 first_done_cyc - first_req_cyc, first_req_cyc, first_done_cyc);

        errors = 0;
        for (w = 0; w < 4; w = w + 1)
            for (i = 0; i < 16; i = i + 1) begin
                exp = 3*(w*16 + i) + 'h100;
                if (debug_regs[w][i][4] !== exp[15:0]) begin
                    errors = errors + 1;
                    $display("  [FAIL] warp %0d lane %0d : R4=%h exp %h",
                             w, i, debug_regs[w][i][4], exp[15:0]);
                end
            end
        $display("\n R4 check (= 3*(warp*16+lane)+0x100): %0d/64 errors -> %s",
                 errors, (errors==0)?"ALL PASS":"FAIL");

        $display("\n data memory (block w, words 0,1,15) -- stored value = 3*gi+0x100:");
        for (w = 0; w < 4; w = w + 1)
            $display("  block %0d : word0=%h word1=%h word15=%h", w,
                dut.dmem.bank[0].u_bank.data_memory[w][15:0],
                dut.dmem.bank[1].u_bank.data_memory[w][15:0],
                dut.dmem.bank[15].u_bank.data_memory[w][15:0]);

        $display("\n=====================================================");
        $display("  OVERALL: %s", (errors==0)?"ALL PASS":"FAIL");
        $display("=====================================================\n");
        $finish;
    end

    integer tlim = 0;
    initial begin
        @(negedge reset);
        $display("\n cyc warp  pc  instr     run req hold done lwR  msState");
        forever begin
            @(posedge clk);
            tlim = tlim + 1;
            if (!reset && tlim <= 60)
                $display(" %3d   W%0d %4h %8h   %b   %b   %b   %b    %b    %0d",
                    cyc, dut.current_warp_id, dut.warp_ready, dut.instr,
                    dut.running, dut.mem_req, dut.hold, dut.mem_done,
                    dut.lw_ready, dut.scheduler_inst.state_curr);
        end
    end
endmodule