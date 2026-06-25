`timescale 1ns/1ps

module tb_warp_scheduler;

    reg clk;
    reg rst;

    reg mem_req;
    reg mem_done;
    reg [1:0] warp_id_from_ms;
    reg [15:0] held_pc;

    reg halt;
    reg hold;
    reg redirect;
    reg [15:0] pc_target;

    wire [1:0] warp_id_to_ms;
    wire [15:0] warp_ready;
    wire [15:0] warp_ready_mask;
    wire [1:0] current_warp_id;
    wire running;
    wire done;

    warp_scheduler dut (
        .clk(clk),
        .rst(rst),
        .mem_req(mem_req),
        .mem_done(mem_done),
        .warp_id_from_ms(warp_id_from_ms),
        .halt(halt),
        .hold(hold),
        .redirect(redirect),
        .pc_target(pc_target),
        .warp_id_to_ms(warp_id_to_ms),
        .warp_ready(warp_ready),
        .warp_ready_mask(warp_ready_mask),
        .current_warp_id(current_warp_id),
        .running(running),
        .done(done)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        $display(
            "T=%0t Warp=%0d PC=%h Running=%b Done=%b Stall[0]=%b Stall[1]=%b redirect=%b",
            $time,
            current_warp_id,
            warp_ready,
            running,
            done,
            dut.WARP_STALL[0],
            dut.WARP_STALL[1],
            redirect
        );
    end

    task check_stall_clear;
        input [1:0] warp_id;
        input integer timeout;
        integer cycles;
        reg stall_cleared;
        begin
            cycles = 0;
            stall_cleared = 1'b0;
            while (cycles < timeout && !stall_cleared) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (dut.WARP_STALL[warp_id] === 1'b0) begin
                    $display("Stall cleared for warp %0d after %0d cycles", warp_id, cycles);
                    stall_cleared = 1'b1;
                end
            end
            if (!stall_cleared) begin
                $display("FAIL: stall not cleared for warp %0d after %0d cycles", warp_id, timeout);
                $finish;
            end
        end
    endtask

    initial begin
        integer i;
        
        rst = 1;
        mem_req = 0;
        mem_done = 0;
        warp_id_from_ms = 0;
        halt = 0;
        hold = 0;
        redirect = 0;
        pc_target = 0;

        // Reset
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        if (current_warp_id !== 2'b00) begin
            $display("FAIL: reset warp");
            $finish;
        end
        if (warp_ready !== 16'h0000) begin
            $display("FAIL: reset pc");
            $finish;
        end
        $display("RESET PASS");

        // PC increment
        @(posedge clk);
        @(posedge clk);
        if (warp_ready !== 16'h0002) begin
            $display("FAIL: PC increment");
            $display("Expected=0002 Got=%h", warp_ready);
            $finish;
        end
        $display("PC INCREMENT PASS");

        // Stall warp0
        mem_req = 1;
        @(posedge clk);
        mem_req = 0;
        repeat(3) @(posedge clk);
        if (current_warp_id !== 2'd1) begin
            $display("FAIL: mem stall switch");
            $finish;
        end
        if (dut.WARP_STALL[0] !== 1'b1) begin
            $display("FAIL: warp0 not stalled");
            $finish;
        end
        $display("MEMORY STALL PASS");

        // Complete warp0 memory
        warp_id_from_ms = 0;
        mem_done = 1;
        @(posedge clk);
        mem_done = 0;
        check_stall_clear(0, 10);
        if (dut.WARP_PC[0] !== 16'h0003) begin
            $display("FAIL: warp0 PC not incremented correctly");
            $display("Expected=0003 Got=%h", dut.WARP_PC[0]);
            $finish;
        end
        $display("MEMORY COMPLETE PASS");

        // -------------------------------------------
        // Redirect test – assert for two full cycles
        // -------------------------------------------
        repeat(2) @(posedge clk);
        $display("PC before redirect = %h", warp_ready);

        // Assert redirect and wait one full cycle
        redirect = 1;
        pc_target = 16'h0200;
        @(posedge clk);               // first edge – redirect sampled

        // Keep redirect high for one more cycle to ensure it's stable
        @(posedge clk);               // second edge – redirect still high

        // Now deassert and check
        redirect = 0;
        @(posedge clk);               // third edge – PC should already be updated

        if (warp_ready !== 16'h0200) begin
            $display("FAIL: redirect");
            $display("PC=%h Expected=0200", warp_ready);
            $finish;
        end
        $display("REDIRECT PASS");

        // Hold test
        held_pc = warp_ready;
        hold = 1;
        @(posedge clk);
        @(posedge clk);
        if (warp_ready !== held_pc) begin
            $display("FAIL: hold");
            $display("Expected=%h Got=%h", held_pc, warp_ready);
            $finish;
        end
        hold = 0;
        $display("HOLD PASS");

        // Halt warp1
        $display("Halting warp %0d", current_warp_id);
        halt = 1;
        repeat(3) @(posedge clk);
        halt = 0;
        repeat(3) @(posedge clk);
        if (dut.WARP_FINISHED[1] !== 1'b1) begin
            $display("FAIL: warp1 not finished");
            $finish;
        end
        if (current_warp_id == 2'd1) begin
            $display("FAIL: scheduler stayed on halted warp");
            $finish;
        end
        $display("HALT PASS");

        // Halt remaining warps
        while (!done) begin
            @(posedge clk);
            if (running && !dut.WARP_FINISHED[current_warp_id]) begin
                $display("Halting warp %0d", current_warp_id);
                halt = 1;
                repeat(3) @(posedge clk);
                halt = 0;
            end
        end

        // Final checks
        if (!done) begin
            $display("FAIL: done not asserted");
            $finish;
        end
        for (i = 0; i < 4; i = i + 1) begin
            if (!dut.WARP_FINISHED[i]) begin
                $display("FAIL: warp %0d not finished", i);
                $finish;
            end
        end

        $display("");
        $display("==================================");
        $display("WARP SCHEDULER TEST PASSED");
        $display("==================================");
        $display("");
        $finish;
    end
endmodule