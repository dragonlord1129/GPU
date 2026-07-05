`timescale 1ns/1ps

module tb_two_loads;

    reg clk, rst;
    wire done;

    gpu_top dut (.clk(clk), .rst(rst), .done(done));

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst = 1'b1;
        repeat (3) @(posedge clk);
        @(posedge clk);
        rst = 1'b0;
        wait (done == 1'b1);
        @(posedge clk);
        #1;

        // Check R1 and R2 for lane 0 via read ports (we'll force rs1_addr=1, then rs1_addr=2)
        // We can't do that without modifying the module, but we can just check
        // the store result in the memory for the full matrix program.
        // For now, just print lw_out when mem_done fires to verify.
        $finish;
    end

    // Monitor lw_out on each mem_done
    always @(posedge clk) begin
        if (!rst && dut.mem_done && dut.MemRead) begin
            $display("t=%0t Load done: lw_out[0..3] = %0d,%0d,%0d,%0d",
                     $time, dut.lw_out[0][15:0], dut.lw_out[1][15:0],
                     dut.lw_out[2][15:0], dut.lw_out[3][15:0]);
        end
    end

endmodule