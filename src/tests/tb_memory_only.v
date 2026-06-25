`timescale 1ns / 1ps

module tb_memory_only;

    reg clk, reset;
    reg [3:0] request;
    reg [15:0] active_mask;
    reg [15:0] addr_in [0:15];
    reg [15:0] sw_out [0:15];
    wire [15:0] lw_out [0:15];
    wire stall;
    wire mem_write;
    reg mem_req;
    reg [1:0] warp_id_from_ws;
    wire mem_done;
    wire [1:0] warp_id_to_ws;
    reg [3:0] lw_destination;
    wire [3:0] lw_destination_out;
    wire [15:0] lw_line_in [0:15];
    wire [15:0] addr_out;
    wire [15:0] sw_line_out [0:15];
    wire [15:0] sw_word_mask;
    wire [1:0] lw_warp_id;
    wire lw_ready;

    // Memory scheduler
    memory_scheduler #(.LINE_WORDS(16), .OFFSET_BITS(4)) MS (
        .clk            (clk),
        .reset          (reset),
        .request        (request),
        .active_mask    (active_mask),
        .addr_in        (addr_in),
        .sw_out         (sw_out),
        .lw_out         (lw_out),
        .stall          (stall),
        .mem_write      (mem_write),
        .mem_req        (mem_req),
        .warp_id_from_ws(warp_id_from_ws),
        .mem_done       (mem_done),
        .warp_id_to_ws  (warp_id_to_ws),
        .lw_destination (lw_destination),
        .lw_destination_out(lw_destination_out),
        .lw_line_in     (lw_line_in),
        .addr_out       (addr_out),
        .sw_line_out    (sw_line_out),
        .sw_word_mask   (sw_word_mask),
        .lw_warp_id     (lw_warp_id),
        .lw_ready       (lw_ready)
    );

    // Data memory line
    data_memory_line #(.LINE_WORDS(16), .OFFSET_BITS(4)) DMEM (
        .clk          (clk),
        .mem_write    (mem_write),
        .addr_base    (addr_out),
        .sw_word_mask (sw_word_mask),
        .sw_line_out  (sw_line_out),
        .lw_line_in   (lw_line_in)
    );

    // Clock
    always #5 clk = ~clk;

    integer i;

    // Helper task to issue a request
    task issue_request(input [3:0] req_type, input [1:0] warp, input [15:0] addr0, input [15:0] data0);
        begin
            @(posedge clk);
            mem_req = 1;
            request = req_type;
            warp_id_from_ws = warp;
            addr_in[0] = addr0;
            sw_out[0] = data0;
            @(posedge clk);
            mem_req = 0;
            request = 4'b0000;
        end
    endtask

    // Helper task to wait for mem_done
    task wait_done;
        begin
            @(posedge clk);
            while (!mem_done) @(posedge clk);
            // Wait one more cycle to let lw_ready settle if it's a load
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        active_mask = 16'hFFFF;
        warp_id_from_ws = 2'b00;
        lw_destination = 4'h1;
        mem_req = 0;
        request = 4'b0000;

        // Initialise address/data arrays
        for (i = 0; i < 16; i = i + 1) begin
            addr_in[i] = 0;
            sw_out[i]  = 0;
        end

        // Preload data memory bank 0 with test value at line 0
        DMEM.bank[0].u_bank.data_memory[0] = 100;

        #10 reset = 0;

        // ---- Test 1: Load from address 0 ----
        issue_request(4'b0110, 2'b00, 0, 0);
        wait_done();

        // Now read lw_out when lw_ready is high
        @(posedge clk);
        while (!lw_ready) @(posedge clk);

        if (lw_out[0] === 16'd100) begin
            $display("PASS: Load from address 0 returned 100");
        end else begin
            $display("FAIL: Load from address 0 returned %0d, expected 100", lw_out[0]);
        end

        // ---- Test 2: Store to address 8 ----
        issue_request(4'b0111, 2'b00, 8, 42);
        wait_done();

        // ---- Test 3: Load from address 8 to verify store ----
        issue_request(4'b0110, 2'b00, 8, 0);
        wait_done();

        @(posedge clk);
        while (!lw_ready) @(posedge clk);

        if (lw_out[0] === 16'd42) begin
            $display("PASS: Load from address 8 returned 42 (store succeeded)");
        end else begin
            $display("FAIL: Load from address 8 returned %0d, expected 42", lw_out[0]);
        end

        // ---- Test 4: Direct memory check ----
        if (DMEM.bank[8].u_bank.data_memory[0] == 32'd42) begin
            $display("PASS: Memory bank 8 contains 42");
        end else begin
            $display("FAIL: Memory bank 8 contains %0d, expected 42", DMEM.bank[8].u_bank.data_memory[0]);
        end

        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_memory_only.vcd");
        $dumpvars(0, tb_memory_only);
    end

endmodule