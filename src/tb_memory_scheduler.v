`timescale 1ns/1ps
// ============================================================================
//  tb_memory_scheduler.v   (pure Verilog, Verilog-2001 style)
//
//  Self-checking testbench for the coalescing memory_scheduler.
//
//  It also contains data_memory_model: a behavioural memory that honours the
//  "WIDENED DATA-MEMORY CONTRACT" described in the DUT header
//    * word addressed, 16-bit words
//    * a line = LINE_WORDS consecutive words aligned on LINE_WORDS
//    * synchronous, 1-cycle latency (this is what the WAIT state pays for)
//        - every clock it registers the line at addr_out onto lw_line_in
//        - if mem_write it performs a *masked* read-modify-write of that line
//
//  NOTE ON LANGUAGE / TOOLCHAIN
//  ----------------------------
//  This file is written in classic Verilog (reg/wire, integer, $sformat,
//  non-automatic tasks, no SystemVerilog data types).  The DUT itself,
//  however, uses two SystemVerilog-only features - unpacked ARRAY PORTS
//  (addr_in[0:15], lw_out[0:15], lw_line_in[...], sw_line_out[...]) and
//  variable declarations inside unnamed begin/end blocks - so the design as
//  a whole must still be compiled with Icarus' Verilog-2005+SV mode.  The
//  testbench connects to the DUT's array ports by name; that is the only
//  point where SystemVerilog is unavoidable, and it lives in the DUT.
//
//  Run:
//    iverilog -g2005-sv -o sim memory_scheduler.sv tb_memory_scheduler.v
//    vvp sim
//  (-g2012 also works.)  Waveform: gtkwave tb.vcd
// ============================================================================

// ----------------------------------------------------------------------------
//  Behavioural data memory honouring the widened contract
// ----------------------------------------------------------------------------
module data_memory_model #(
    parameter LINE_WORDS  = 16,
    parameter OFFSET_BITS = 4,
    parameter MEM_WORDS   = (1<<16)            // full 16-bit word space
) (
    input                   clk,
    input  [15:0]           addr_out,                    // line base
    input                   mem_write,
    input  [15:0]           sw_line_out [0:LINE_WORDS-1],
    input  [LINE_WORDS-1:0] sw_word_mask,
    output reg [15:0]       lw_line_in  [0:LINE_WORDS-1]
);
    reg [15:0] mem [0:MEM_WORDS-1];

    // belt-and-braces: force the request onto a line boundary
    wire [15:0] base = addr_out & {{(16-OFFSET_BITS){1'b1}}, {OFFSET_BITS{1'b0}}};

    integer k;

    // synchronous read -> presents the whole line one cycle later
    always @(posedge clk) begin
        for (k = 0; k < LINE_WORDS; k = k + 1)
            lw_line_in[k] <= mem[base + k];
    end

    // synchronous masked write (only masked words change)
    always @(posedge clk) begin
        if (mem_write) begin
            for (k = 0; k < LINE_WORDS; k = k + 1)
                if (sw_word_mask[k])
                    mem[base + k] <= sw_line_out[k];
        end
    end
endmodule


// ----------------------------------------------------------------------------
//  Testbench
// ----------------------------------------------------------------------------
module tb_memory_scheduler;

    localparam        LINE_WORDS  = 16;
    localparam        OFFSET_BITS = 4;
    localparam [2:0]  S_WAIT      = 3'b100;    // must match DUT WAIT encoding

    localparam [3:0]  REQ_LOAD    = 4'b0110;   // the DUT treats 0110 as a load
    localparam [3:0]  REQ_STORE   = 4'b0101;   // anything != 0110 is a store

    // ---- clock / reset -----------------------------------------------------
    reg clk;
    initial clk = 1'b0;
    always #5 clk = ~clk;                       // 100 MHz
    reg reset;

    // ---- DUT <-> TB / memory wiring ---------------------------------------
    //  TB-driven stimulus  -> reg
    //  DUT / memory outputs -> wire  (unpacked array module-outputs MUST be a
    //  net in Icarus, or the value will not propagate through the port)
    reg  [3:0]             request;
    reg  [15:0]            active_mask;
    reg  [15:0]            addr_in [0:15];
    reg  [15:0]            sw_out  [0:15];
    wire [15:0]            lw_out  [0:15];   // DUT output
    wire                   stall;
    wire                   mem_write;

    reg                    mem_req;
    reg  [1:0]             warp_id_from_ws;
    wire                   mem_done;
    wire [1:0]             warp_id_to_ws;
    reg  [3:0]             lw_destination;
    wire [3:0]             lw_destination_out;

    wire [15:0]            lw_line_in  [0:LINE_WORDS-1];  // mem output -> DUT input
    wire [15:0]            addr_out;
    wire [15:0]            sw_line_out [0:LINE_WORDS-1];  // DUT output -> mem input
    wire [LINE_WORDS-1:0]  sw_word_mask;

    wire [1:0]             lw_warp_id;
    wire                   lw_ready;

    // ---- DUT ---------------------------------------------------------------
    memory_scheduler #(.LINE_WORDS(LINE_WORDS), .OFFSET_BITS(OFFSET_BITS)) dut (
        .clk(clk), .reset(reset),
        .request(request), .active_mask(active_mask),
        .addr_in(addr_in), .sw_out(sw_out), .lw_out(lw_out),
        .stall(stall), .mem_write(mem_write),
        .mem_req(mem_req), .warp_id_from_ws(warp_id_from_ws),
        .mem_done(mem_done), .warp_id_to_ws(warp_id_to_ws),
        .lw_destination(lw_destination), .lw_destination_out(lw_destination_out),
        .lw_line_in(lw_line_in), .addr_out(addr_out),
        .sw_line_out(sw_line_out), .sw_word_mask(sw_word_mask),
        .lw_warp_id(lw_warp_id), .lw_ready(lw_ready)
    );

    // ---- memory model ------------------------------------------------------
    data_memory_model #(.LINE_WORDS(LINE_WORDS), .OFFSET_BITS(OFFSET_BITS)) u_mem (
        .clk(clk), .addr_out(addr_out), .mem_write(mem_write),
        .sw_line_out(sw_line_out), .sw_word_mask(sw_word_mask),
        .lw_line_in(lw_line_in)
    );

    // ---- golden memory contents (single source of truth) -------------------
    function [15:0] mem_init;
        input [15:0] a;
        begin
            mem_init = a ^ 16'hC3C3;            // scrambled, bijective in 'a'
        end
    endfunction

    integer a;
    initial begin
        for (a = 0; a < (1<<16); a = a + 1)
            u_mem.mem[a] = mem_init(a[15:0]);   // memory model starts == golden
    end

    // ---- score keeping -----------------------------------------------------
    integer       checks = 0;
    integer       errors = 0;
    reg [80*8-1:0] msg;                          // packed-string scratch

    task check;
        input         cond;
        input [80*8-1:0] m;
        begin
            checks = checks + 1;
            if (cond) $display("    [PASS] %0s", m);
            else begin errors = errors + 1; $display("    [FAIL] %0s", m); end
        end
    endtask

    // ---- transaction monitor: counts WAIT entries, logs + protocol-checks --
    integer     txn_count    = 0;
    integer     proto_errors = 0;
    reg [2:0]   prev_state   = 3'b000;

    always @(posedge clk) begin
        if (reset) begin
            txn_count    <= 0;
            proto_errors <= 0;
            prev_state   <= 3'b000;
        end else begin
            if ((dut.state_curr == S_WAIT) && (prev_state != S_WAIT)) begin
                // a fresh memory transaction is being issued this cycle
                txn_count <= txn_count + 1;
                $display("      . MEM TXN #%0d  base=0x%04h  %0s  members=%016b  mask=%016b",
                         txn_count + 1, addr_out,
                         dut.request_reg ? "LOAD " : "STORE",
                         dut.block_members, sw_word_mask);
                // protocol: a line transaction must be line-aligned
                if (addr_out[OFFSET_BITS-1:0] !== {OFFSET_BITS{1'b0}}) begin
                    proto_errors <= proto_errors + 1;
                    $display("    [FAIL] addr_out 0x%04h not line-aligned", addr_out);
                end
                // protocol: mem_write must be low during a LOAD transaction
                if (dut.request_reg && (mem_write !== 1'b0)) begin
                    proto_errors <= proto_errors + 1;
                    $display("    [FAIL] mem_write asserted during a LOAD");
                end
            end
            prev_state <= dut.state_curr;
        end
    end

    // ---- stimulus helpers --------------------------------------------------
    task do_reset;
        integer k;
        begin
            reset           = 1'b1;
            mem_req         = 1'b0;
            request         = 4'b0000;
            active_mask     = 16'h0000;
            warp_id_from_ws = 2'b00;
            lw_destination  = 4'h0;
            for (k = 0; k < 16; k = k + 1) begin
                addr_in[k] = 16'h0;
                sw_out[k]  = 16'h0;
            end
            repeat (3) @(negedge clk);
            reset = 1'b0;
            @(negedge clk);
        end
    endtask

    // issue a single one-cycle request pulse (does NOT wait for completion)
    task fire;
        input       is_load;
        input [1:0] wid;
        input [3:0] dest;
        begin
            @(negedge clk);
            request         = is_load ? REQ_LOAD : REQ_STORE;
            warp_id_from_ws = wid;
            lw_destination  = dest;
            mem_req         = 1'b1;
            @(negedge clk);
            mem_req         = 1'b0;
            request         = 4'b0000;
        end
    endtask

    // wait for the next completion pulse (mem_done) - classic Verilog, no do/while
    task wait_done;
        begin
            @(posedge clk);
            while (mem_done !== 1'b1) @(posedge clk);
        end
    endtask

    // ---- expectation bookkeeping ------------------------------------------
    reg [15:0] exp     [0:15];
    reg [15:0] prev_lw [0:15];
    integer    base_txn, actual_txn, L;
    reg [15:0] BASE, BASEA, BASEB;

    // =======================================================================
    //  TEST SEQUENCE
    // =======================================================================
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb_memory_scheduler);

        do_reset;

        // -------------------------------------------------------------------
        $display("\n=== TEST 1 : perfect coalescing, 16 lanes -> 1 line (LOAD) ===");
        BASE = 16'h0100;
        active_mask = 16'hFFFF;
        for (L = 0; L < 16; L = L + 1) begin
            addr_in[L] = BASE + L;              // offsets 0..15 in one line
            exp[L]     = mem_init(addr_in[L]);
        end
        base_txn = txn_count;
        fire(1'b1, 2'd0, 4'h5);
        wait_done;
        actual_txn = txn_count - base_txn;
        for (L = 0; L < 16; L = L + 1) begin
            $sformat(msg, "lane %0d  lw_out=0x%04h exp=0x%04h", L, lw_out[L], exp[L]);
            check(lw_out[L] === exp[L], msg);
        end
        $sformat(msg, "transactions = %0d (expected 1, fully coalesced)", actual_txn);
        check(actual_txn === 1, msg);
        $sformat(msg, "lw_warp_id = %0d (exp 0)", lw_warp_id);
        check(lw_warp_id === 2'd0, msg);
        $sformat(msg, "warp_id_to_ws = %0d (exp 0)", warp_id_to_ws);
        check(warp_id_to_ws === 2'd0, msg);
        $sformat(msg, "lw_destination_out = 0x%0h (exp 5)", lw_destination_out);
        check(lw_destination_out === 4'h5, msg);
        repeat (2) @(negedge clk);

        // -------------------------------------------------------------------
        $display("\n=== TEST 2 : fully scattered, 16 lanes -> 16 lines (LOAD) ===");
        active_mask = 16'hFFFF;
        for (L = 0; L < 16; L = L + 1) begin
            addr_in[L] = (L*LINE_WORDS) + 3;    // distinct block each, offset 3
            exp[L]     = mem_init(addr_in[L]);
        end
        base_txn = txn_count;
        fire(1'b1, 2'd1, 4'h6);
        wait_done;
        actual_txn = txn_count - base_txn;
        for (L = 0; L < 16; L = L + 1) begin
            $sformat(msg, "lane %0d  lw_out=0x%04h exp=0x%04h", L, lw_out[L], exp[L]);
            check(lw_out[L] === exp[L], msg);
        end
        $sformat(msg, "transactions = %0d (expected 16, fully scattered)", actual_txn);
        check(actual_txn === 16, msg);
        $sformat(msg, "lw_warp_id = %0d (exp 1)", lw_warp_id);
        check(lw_warp_id === 2'd1, msg);
        repeat (2) @(negedge clk);

        // -------------------------------------------------------------------
        $display("\n=== TEST 3 : partial active_mask (only 8 lanes), 1 line (LOAD) ===");
        // keep TEST 2's results to prove inactive lanes are left untouched
        for (L = 0; L < 16; L = L + 1) prev_lw[L] = lw_out[L];
        BASE = 16'h0600;
        active_mask = 16'h0F0F;                 // lanes 0-3 and 8-11 active
        for (L = 0; L < 16; L = L + 1) begin
            addr_in[L] = BASE + L;
            exp[L]     = mem_init(addr_in[L]);
        end
        base_txn = txn_count;
        fire(1'b1, 2'd2, 4'h7);
        wait_done;
        actual_txn = txn_count - base_txn;
        for (L = 0; L < 16; L = L + 1) begin
            if (active_mask[L]) begin
                $sformat(msg, "active lane %0d  lw_out=0x%04h exp=0x%04h", L, lw_out[L], exp[L]);
                check(lw_out[L] === exp[L], msg);
            end else begin
                $sformat(msg, "inactive lane %0d untouched (0x%04h)", L, lw_out[L]);
                check(lw_out[L] === prev_lw[L], msg);
            end
        end
        $sformat(msg, "transactions = %0d (expected 1)", actual_txn);
        check(actual_txn === 1, msg);
        repeat (2) @(negedge clk);

        // -------------------------------------------------------------------
        $display("\n=== TEST 4 : two half-warps -> 2 lines (LOAD) ===");
        BASEA = 16'h0200; BASEB = 16'h0300;
        active_mask = 16'hFFFF;
        for (L = 0; L < 16; L = L + 1) begin
            if (L < 8) addr_in[L] = BASEA + L;          // lanes 0-7  -> line A
            else       addr_in[L] = BASEB + (L-8);      // lanes 8-15 -> line B
            exp[L] = mem_init(addr_in[L]);
        end
        base_txn = txn_count;
        fire(1'b1, 2'd3, 4'h2);
        wait_done;
        actual_txn = txn_count - base_txn;
        for (L = 0; L < 16; L = L + 1) begin
            $sformat(msg, "lane %0d  lw_out=0x%04h exp=0x%04h", L, lw_out[L], exp[L]);
            check(lw_out[L] === exp[L], msg);
        end
        $sformat(msg, "transactions = %0d (expected 2)", actual_txn);
        check(actual_txn === 2, msg);
        repeat (2) @(negedge clk);

        // -------------------------------------------------------------------
        $display("\n=== TEST 5 : perfect-coalesced STORE then load-back ===");
        BASE = 16'h0400;
        active_mask = 16'hFFFF;
        for (L = 0; L < 16; L = L + 1) begin
            addr_in[L] = BASE + L;
            sw_out[L]  = 16'hD000 + L;
            exp[L]     = 16'hD000 + L;
        end
        base_txn = txn_count;
        fire(1'b0, 2'd0, 4'h0);   // STORE
        wait_done;
        actual_txn = txn_count - base_txn;
        $sformat(msg, "store transactions = %0d (expected 1)", actual_txn);
        check(actual_txn === 1, msg);
        repeat (2) @(negedge clk);
        // load it back
        for (L = 0; L < 16; L = L + 1) addr_in[L] = BASE + L;
        fire(1'b1, 2'd0, 4'h1);   // LOAD
        wait_done;
        for (L = 0; L < 16; L = L + 1) begin
            $sformat(msg, "loaded-back lane %0d  lw_out=0x%04h exp=0x%04h", L, lw_out[L], exp[L]);
            check(lw_out[L] === exp[L], msg);
        end
        repeat (2) @(negedge clk);

        // -------------------------------------------------------------------
        $display("\n=== TEST 6 : partial-mask STORE (read-modify-write check) ===");
        BASE = 16'h0500;
        active_mask = 16'h00FF;                 // store only words 0..7 of the line
        for (L = 0; L < 16; L = L + 1) begin
            addr_in[L] = BASE + L;
            sw_out[L]  = 16'hE000 + L;
        end
        fire(1'b0, 2'd1, 4'h0);   // STORE
        wait_done;
        repeat (2) @(negedge clk);
        // read the WHOLE line back: 0..7 should be new, 8..15 should be untouched
        active_mask = 16'hFFFF;
        for (L = 0; L < 16; L = L + 1) begin
            addr_in[L] = BASE + L;
            exp[L]     = (L < 8) ? (16'hE000 + L) : mem_init(BASE + L);
        end
        fire(1'b1, 2'd1, 4'h2);   // LOAD
        wait_done;
        for (L = 0; L < 16; L = L + 1) begin
            $sformat(msg, "word %0d  lw_out=0x%04h exp=0x%04h (%0s)",
                     L, lw_out[L], exp[L], (L<8) ? "stored" : "untouched");
            check(lw_out[L] === exp[L], msg);
        end
        repeat (2) @(negedge clk);

        // -------------------------------------------------------------------
        $display("\n=== TEST 7 : scattered STORE -> 16 lines, then load-back ===");
        active_mask = 16'hFFFF;
        for (L = 0; L < 16; L = L + 1) begin
            addr_in[L] = 16'h1000 + (L*LINE_WORDS) + 7;   // distinct line, offset 7
            sw_out[L]  = 16'h7000 + L;
            exp[L]     = 16'h7000 + L;
        end
        base_txn = txn_count;
        fire(1'b0, 2'd2, 4'h0);   // STORE
        wait_done;
        actual_txn = txn_count - base_txn;
        $sformat(msg, "store transactions = %0d (expected 16)", actual_txn);
        check(actual_txn === 16, msg);
        repeat (2) @(negedge clk);
        // load back the same scattered addresses
        for (L = 0; L < 16; L = L + 1) addr_in[L] = 16'h1000 + (L*LINE_WORDS) + 7;
        fire(1'b1, 2'd2, 4'h3);   // LOAD
        wait_done;
        for (L = 0; L < 16; L = L + 1) begin
            $sformat(msg, "loaded-back lane %0d  lw_out=0x%04h exp=0x%04h", L, lw_out[L], exp[L]);
            check(lw_out[L] === exp[L], msg);
        end
        repeat (2) @(negedge clk);

        // -------------------------------------------------------------------
        $display("\n=== TEST 8 : two warps queued back-to-back (LOAD, LOAD) ===");
        // warp A (id 1) and warp B (id 2), each a perfectly-coalesced load.
        // B is injected while A is still in flight.
        BASEA = 16'h2000; BASEB = 16'h2100;
        // -- fire A --
        active_mask = 16'hFFFF;
        for (L = 0; L < 16; L = L + 1) addr_in[L] = BASEA + L;
        fire(1'b1, 2'd1, 4'h3);
        // -- fire B (while A still processing) --
        for (L = 0; L < 16; L = L + 1) addr_in[L] = BASEB + L;
        fire(1'b1, 2'd2, 4'h4);

        // first completion should be warp A
        wait_done;
        $sformat(msg, "1st done: warp_id_to_ws = %0d (exp 1=A)", warp_id_to_ws);
        check(warp_id_to_ws === 2'd1, msg);
        $sformat(msg, "1st done: dest = 0x%0h (exp 3)", lw_destination_out);
        check(lw_destination_out === 4'h3, msg);
        for (L = 0; L < 16; L = L + 1) begin
            $sformat(msg, "warpA lane %0d  lw_out=0x%04h exp=0x%04h", L, lw_out[L], mem_init(BASEA+L));
            check(lw_out[L] === mem_init(BASEA + L), msg);
        end

        // second completion should be warp B
        wait_done;
        $sformat(msg, "2nd done: warp_id_to_ws = %0d (exp 2=B)", warp_id_to_ws);
        check(warp_id_to_ws === 2'd2, msg);
        $sformat(msg, "2nd done: dest = 0x%0h (exp 4)", lw_destination_out);
        check(lw_destination_out === 4'h4, msg);
        for (L = 0; L < 16; L = L + 1) begin
            $sformat(msg, "warpB lane %0d  lw_out=0x%04h exp=0x%04h", L, lw_out[L], mem_init(BASEB+L));
            check(lw_out[L] === mem_init(BASEB + L), msg);
        end
        repeat (2) @(negedge clk);

        // -------------------------------------------------------------------
        errors = errors + proto_errors;
        $display("\n==========================================================");
        $display("  SUMMARY : %0d checks, %0d failures (incl. %0d protocol)",
                 checks, errors, proto_errors);
        if (errors == 0) $display("  RESULT  : ALL TESTS PASSED");
        else             $display("  RESULT  : THERE WERE FAILURES");
        $display("==========================================================\n");
        $finish;
    end

    // ---- watchdog ----------------------------------------------------------
    initial begin
        #200000;
        $display("\n[TIMEOUT] simulation did not finish - the FSM may be stuck.");
        $finish;
    end

endmodule