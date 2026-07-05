`timescale 1ns/1ps

module tb_gpu_diag_detail;

    reg clk;
    reg rst;
    wire done;

    gpu_top dut (.clk(clk), .rst(rst), .done(done));

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Count loads and print lw_out when each load completes
    // ----------------------------------------------------------------
    reg load_count;
    initial load_count = 0;

    always @(posedge clk) begin
        if (!rst && dut.mem_done && dut.mem_is_load[dut.ms_warp_id_to_ws]) begin
            load_count <= load_count + 1;
            #1;
            $display("t=%0t Load #%0d completed: dest=R%0d, lw_out[0..3]=%0d,%0d,%0d,%0d",
                     $time, load_count,
                     dut.mem_dest[dut.ms_warp_id_to_ws],
                     dut.lw_out[0][15:0], dut.lw_out[1][15:0], dut.lw_out[2][15:0], dut.lw_out[3][15:0]);
        end
    end

    // ----------------------------------------------------------------
    // Run program, then dump critical registers
    // ----------------------------------------------------------------
    integer lane;
    initial begin
        rst = 1'b1;
        repeat (3) @(posedge clk);
        @(posedge clk);
        rst = 1'b0;

        wait (done == 1'b1);
        @(posedge clk);
        #1;

        $display("\n=== Post‑mortem register dump ===");
        $display("Lane  R1(A) R2(B) R3(sum) R4(r) R5(c) R12(idx) R13(addr)");
        for (lane = 0; lane < 16; lane = lane + 1) begin
            $display(" %2d   %4d  %4d   %4d     %4d   %4d    %4d     %4d",
                     lane,
                     dut.u_regfile.REGS[lane][1],
                     dut.u_regfile.REGS[lane][2],
                     dut.u_regfile.REGS[lane][3],
                     dut.u_regfile.REGS[lane][4],
                     dut.u_regfile.REGS[lane][5],
                     dut.u_regfile.REGS[lane][12],
                     dut.u_regfile.REGS[lane][13]);
        end

        $finish;
    end

    // Safety timeout
    initial begin
        #500000;
        $display("TIMEOUT");
        $finish;
    end

endmodule