`timescale 1ns / 1ps

module tb_stress;
    reg         clk;
    reg         rst;
    reg  [15:0] block_idx;
    reg  [15:0] block_dim;
    reg  [15:0] thread_idx_base;
    wire        done;

    gpu_top uut (
        .clk            (clk),
        .rst            (rst),
        .block_idx      (block_idx),
        .block_dim      (block_dim),
        .thread_idx_base(thread_idx_base),
        .done           (done)
    );

    always #5 clk = ~clk;

    initial begin
        clk   = 0;
        rst   = 1;
        block_idx       = 16'h0000;
        block_dim       = 16'h0000;
        thread_idx_base = 16'h0000;

        // Preload data memory using hex files
        $readmemh("bank5.hex", uut.u_data_mem.bank[5].u_bank.data_memory);
        $readmemh("bank6.hex", uut.u_data_mem.bank[6].u_bank.data_memory);

        #20 rst = 0;

        wait(done == 1'b1);
        #20;

        if (uut.u_data_mem.bank[7].u_bank.data_memory[8'h80] === 32'h0000_000F)
            $display("TEST PASSED: Memory[0x0807] = %h",
                     uut.u_data_mem.bank[7].u_bank.data_memory[8'h80]);
        else
            $display("TEST FAILED: Memory[0x0807] = %h (expected 0x000F)",
                     uut.u_data_mem.bank[7].u_bank.data_memory[8'h80]);

        $finish;
    end

    initial begin
        $monitor("Time=%0t: done=%b", $time, done);
    end
endmodule