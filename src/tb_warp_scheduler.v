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

    //-----------------------------------------
    // DUT
    //-----------------------------------------

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

    //-----------------------------------------
    // Clock
    //-----------------------------------------

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //-----------------------------------------
    // Monitor
    //-----------------------------------------

    always @(posedge clk) begin
        $display(
            "T=%0t Warp=%0d PC=%h Running=%b Done=%b",
            $time,
            current_warp_id,
            warp_ready,
            running,
            done
        );
    end

    //-----------------------------------------
    // Main Test
    //-----------------------------------------

    initial begin

        rst = 1;
        mem_req = 0;
        mem_done = 0;
        warp_id_from_ms = 0;
        halt = 0;
        hold = 0;
        redirect = 0;
        pc_target = 0;

        //-------------------------------------
        // Reset
        //-------------------------------------

        repeat(4) @(posedge clk);
        rst = 0;

        @(posedge clk);

        if(current_warp_id !== 2'b00) begin
            $display("FAIL: reset warp");
            $finish;
        end

        if(warp_ready !== 16'h0000) begin
            $display("FAIL: reset pc");
            $finish;
        end

        $display("RESET PASS");

        //-------------------------------------
        // PC increment
        //-------------------------------------

        @(posedge clk);
        @(posedge clk);

        if(warp_ready !== 16'h0002) begin
            $display("FAIL: PC increment");
            $display("Expected=0002 Got=%h", warp_ready);
            $finish;
        end

        $display("PC INCREMENT PASS");

        //-------------------------------------
        // Stall warp0
        //-------------------------------------

        mem_req = 1;
        @(posedge clk);
        mem_req = 0;

        repeat(2) @(posedge clk);

        if(current_warp_id !== 2'd1) begin
            $display("FAIL: mem stall switch");
            $finish;
        end

        $display("MEMORY STALL PASS");

        //-------------------------------------
        // Complete warp0 memory
        //-------------------------------------

        warp_id_from_ms = 0;

        mem_done = 1;
        @(posedge clk);
        mem_done = 0;

        repeat(2) @(posedge clk);

        if(dut.WARP_STALL[0] !== 1'b0) begin
            $display("FAIL: stall clear");
            $finish;
        end

        $display("MEMORY COMPLETE PASS");

        //-------------------------------------
        // Redirect
        //-------------------------------------

        $display("PC before redirect = %h", warp_ready);

        redirect = 1;
        pc_target = 16'h0200;

        @(posedge clk);

        redirect = 0;

        @(posedge clk);

        if(warp_ready < 16'h0200) begin
            $display("FAIL: redirect");
            $display("PC=%h", warp_ready);
            $finish;
        end

        $display("REDIRECT PASS");
        $display("PC after redirect = %h", warp_ready);

        //-------------------------------------
        // Hold
        //-------------------------------------

     
        held_pc = warp_ready;

        hold = 1;

        @(posedge clk);
        @(posedge clk);

        if(warp_ready !== held_pc) begin
            $display("FAIL: hold");
            $display("Expected=%h Got=%h",
                     held_pc, warp_ready);
            $finish;
        end

        hold = 0;

        $display("HOLD PASS");

        //-------------------------------------
        // Halt warp1
        //-------------------------------------

        $display("Halting warp %0d", current_warp_id);

        halt = 1;

        repeat(3) @(posedge clk);

        halt = 0;

        repeat(3) @(posedge clk);

        if(dut.WARP_FINISHED[1] !== 1'b1) begin
            $display("FAIL: warp1 not finished");
            $finish;
        end

        if(current_warp_id == 2'd1) begin
            $display("FAIL: scheduler stayed on halted warp");
            $finish;
        end

        $display("HALT PASS");

        //-------------------------------------
        // Halt remaining warps
        //-------------------------------------

        while(!done) begin

            $display("Halting warp %0d", current_warp_id);

            halt = 1;

            repeat(3) @(posedge clk);

            halt = 0;

            repeat(3) @(posedge clk);

        end

        //-------------------------------------
        // Final checks
        //-------------------------------------

        if(!done) begin
            $display("FAIL: done not asserted");
            $finish;
        end

        $display("");
        $display("==================================");
        $display("WARP SCHEDULER TEST PASSED");
        $display("==================================");
        $display("");

        $finish;

    end

endmodule