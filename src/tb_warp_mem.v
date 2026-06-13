`timescale 1ns/1ps
// ============================================================================
//  tb_warp_mem
//  End-to-end bench: warp_scheduler  <->  memory_scheduler  <->  data memory.
//  The TB plays the role of "top / datapath": it presents memory instructions
//  (mem_req + operands) and halts, and checks the data path + the scheduling
//  handshake (stall / un-stall / PC step / coalescing transaction count).
// ============================================================================
module tb_warp_mem;

    localparam LINE_WORDS  = 16;
    localparam OFFSET_BITS = 4;

    localparam [3:0] OP_LW = 4'b0110;  // memory_scheduler treats 0110 as LOAD
    localparam [3:0] OP_SW = 4'b0111;  // anything != 0110 -> STORE

    localparam [2:0] MS_WAIT = 3'b100; // memory_scheduler WAIT state code

    // ---- clock / reset ----
    reg clk = 1'b0;
    reg reset;
    always #5 clk = ~clk;              // 100 MHz

    // ---- top/datapath-driven stimulus ----
    reg         mem_req;
    reg         halt;
    reg  [3:0]  request;
    reg  [15:0] active_mask;
    reg  [15:0] addr_in [0:15];
    reg  [15:0] sw_out  [0:15];
    reg  [3:0]  lw_destination;

    // ---- WS <-> MS handshake ----
    wire [1:0]  ws_warp_id_to_ms;
    wire [1:0]  ms_warp_id_to_ws;
    wire        ms_mem_done;
    wire [15:0] ws_warp_ready;
    wire [15:0] ws_warp_ready_mask;
    wire [1:0]  ws_current_warp_id;
    wire        ws_done;

    // ---- MS data-side outputs ----
    wire [15:0] lw_out [0:15];
    wire        ms_stall;
    wire        ms_mem_write;
    wire [3:0]  ms_lw_destination_out;
    wire [1:0]  ms_lw_warp_id;
    wire        ms_lw_ready;

    // ---- MS <-> data memory (line interface) ----
    wire [15:0] addr_out;
    wire [15:0] sw_line_out [0:LINE_WORDS-1];
    wire [LINE_WORDS-1:0] sw_word_mask;
    wire [15:0] lw_line_in  [0:LINE_WORDS-1];

    // ============================ DUTs ============================
    warp_scheduler #(.NUMBER_OF_WARPS(4)) ws (
        .clk            (clk),
        .rst            (reset),
        .mem_req        (mem_req),
        .mem_done       (ms_mem_done),
        .warp_id_from_ms(ms_warp_id_to_ws),
        .halt           (halt),
        .warp_id_to_ms  (ws_warp_id_to_ms),
        .warp_ready     (ws_warp_ready),
        .warp_ready_mask(ws_warp_ready_mask),
        .current_warp_id(ws_current_warp_id),
        .done           (ws_done)
    );

    memory_scheduler #(.LINE_WORDS(LINE_WORDS), .OFFSET_BITS(OFFSET_BITS)) ms (
        .clk               (clk),
        .reset             (reset),
        .request           (request),
        .active_mask       (active_mask),
        .addr_in           (addr_in),
        .sw_out            (sw_out),
        .lw_out            (lw_out),
        .stall             (ms_stall),
        .mem_write         (ms_mem_write),
        .mem_req           (mem_req),
        .warp_id_from_ws   (ws_warp_id_to_ms),
        .mem_done          (ms_mem_done),
        .warp_id_to_ws     (ms_warp_id_to_ws),
        .lw_destination    (lw_destination),
        .lw_destination_out(ms_lw_destination_out),
        .lw_line_in        (lw_line_in),
        .addr_out          (addr_out),
        .sw_line_out       (sw_line_out),
        .sw_word_mask      (sw_word_mask),
        .lw_warp_id        (ms_lw_warp_id),
        .lw_ready          (ms_lw_ready)
    );

    data_memory_line #(.LINE_WORDS(LINE_WORDS), .OFFSET_BITS(OFFSET_BITS), .INDEX_BITS(8)) dmem (
        .clk         (clk),
        .mem_write   (ms_mem_write),
        .addr_base   (addr_out),
        .sw_word_mask(sw_word_mask),
        .sw_line_out (sw_line_out),
        .lw_line_in  (lw_line_in)
    );

    // ======================= test bookkeeping =======================
    integer errors = 0;
    integer tests  = 0;
    integer last_xact_count;
    integer k, wut;
    reg [15:0] pc_before;

    task check_int;
        input [255:0] tag;
        input integer got;
        input integer exp;
        begin
            tests = tests + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : got %0d expected %0d", tag, got, exp);
            end else
                $display("  [ ok ] %0s : %0d", tag, got);
        end
    endtask

    task chk_pc;
        input [255:0] tag;
        input [15:0]  got;
        input [15:0]  exp;
        begin
            tests = tests + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : got %h expected %h", tag, got, exp);
            end else
                $display("  [ ok ] %0s : %h", tag, got);
        end
    endtask

    task chk_lw;          // check one lane's load result
        input integer idx;
        input [15:0]  exp;
        begin
            tests = tests + 1;
            if (lw_out[idx] !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] lw_out[%0d] = %h, expected %h", idx, lw_out[idx], exp);
            end
            // (silent on pass to keep the log short)
        end
    endtask

    // Pulse mem_req for one cycle, wait for mem_done, and count the number of
    // memory transactions the MS issues (each = one entry into its WAIT state).
    // Leaves one extra cycle so the WS has registered the completion.
    task fire_request;
        input is_load;
        reg  [2:0] prev_state;
        integer    cnt;
        begin
            request = is_load ? OP_LW : OP_SW;
            @(negedge clk);
            mem_req = 1'b1;
            @(negedge clk);            // exactly one posedge of mem_req
            mem_req = 1'b0;

            cnt        = 0;
            prev_state = ms.state_curr;
            while (ms.mem_done !== 1'b1) begin
                @(negedge clk);
                if ((ms.state_curr == MS_WAIT) && (prev_state != MS_WAIT))
                    cnt = cnt + 1;
                prev_state = ms.state_curr;
            end
            last_xact_count = cnt;
            @(negedge clk);            // let WS register mem_done (un-stall)
        end
    endtask

    task run_cycles;
        input integer n;
        integer c;
        begin
            for (c = 0; c < n; c = c + 1) @(negedge clk);
        end
    endtask

    // ============================ stimulus ============================
    initial begin
        $dumpfile("tb_warp_mem.vcd");
        $dumpvars(0, tb_warp_mem);

        mem_req        = 1'b0;
        halt           = 1'b0;
        request        = OP_LW;
        active_mask    = 16'hFFFF;
        lw_destination = 4'h5;
        for (k = 0; k < 16; k = k + 1) begin
            addr_in[k] = 16'h0000;
            sw_out[k]  = 16'h0000;
        end

        // ---- reset (deassert at a negedge, then sample reset state) ----
        reset = 1'b1;
        repeat (4) @(negedge clk);
        reset = 1'b0;

        $display("\n==== reset / initial warp state ====");
        chk_pc   ("WARP_PC[0]",   ws.WARP_PC[0], 16'h0000);
        chk_pc   ("WARP_PC[1]",   ws.WARP_PC[1], 16'h0010);
        chk_pc   ("WARP_PC[2]",   ws.WARP_PC[2], 16'h0020);
        chk_pc   ("WARP_PC[3]",   ws.WARP_PC[3], 16'h0030);
        check_int("current_warp", ws_current_warp_id, 0);
        check_int("done",         ws_done, 0);

        // ---- free run: PCs advance, warp 0 stays active ----
        $display("\n==== free run (PCs advance, warp 0 active) ====");
        run_cycles(4);
        chk_pc   ("WARP_PC[0] after 4 cyc", ws.WARP_PC[0], 16'h0004);
        check_int("still warp 0",            ws_current_warp_id, 0);

        // =====================================================================
        // T1: coalesced STORE then LOAD back (all lanes in one block)
        //      -> exactly 1 transaction each.
        // =====================================================================
        $display("\n==== T1: coalesced STORE + LOAD, block 0x0020 ====");
        for (k = 0; k < 16; k = k + 1) begin
            addr_in[k] = 16'h0020 + k[15:0];   // block 2, words 0..15
            sw_out[k]  = 16'hA000 + k[15:0];
        end
        active_mask = 16'hFFFF;
        fire_request(1'b0);                    // STORE
        check_int("T1 store transactions", last_xact_count, 1);

        for (k = 0; k < 16; k = k + 1) addr_in[k] = 16'h0020 + k[15:0];
        active_mask = 16'hFFFF;
        fire_request(1'b1);                    // LOAD
        check_int("T1 load transactions", last_xact_count, 1);
        for (k = 0; k < 16; k = k + 1) chk_lw(k, 16'hA000 + k[15:0]);
        $display("  (16 lane values verified against A000..A00F)");

        // =====================================================================
        // TW: warp scheduler handshake -- stall, switch, un-stall, PC step.
        // =====================================================================
        $display("\n==== TW: stall / switch / un-stall / PC+1 across a load ====");
        for (k = 0; k < 16; k = k + 1) addr_in[k] = 16'h0020 + k[15:0];
        active_mask = 16'hFFFF;
        request     = OP_LW;

        wut       = ws_current_warp_id;
        pc_before = ws.WARP_PC[wut];     // sampled at this negedge...

        mem_req = 1'b1;                  // ...assert now so the very next posedge
        @(negedge clk);                  //    stalls the warp (PC frozen here)
        mem_req = 1'b0;
        @(negedge clk);
        @(negedge clk);
        check_int("warp stalled", ws.WARP_STALL[wut], 1);
        if (ws_current_warp_id == wut[1:0]) begin
            errors = errors + 1; tests = tests + 1;
            $display("  [FAIL] WS did not switch away from stalled warp %0d", wut);
        end else begin
            tests = tests + 1;
            $display("  [ ok ] WS switched %0d -> %0d", wut, ws_current_warp_id);
        end

        while (ms.mem_done !== 1'b1) @(negedge clk);
        for (k = 0; k < 16; k = k + 1) chk_lw(k, 16'hA000 + k[15:0]);
        check_int("lw_destination_out", ms_lw_destination_out, 5);
        check_int("lw_warp_id",          ms_lw_warp_id, wut);

        @(negedge clk);                         // WS registers mem_done
        check_int("warp un-stalled", ws.WARP_STALL[wut], 0);
        chk_pc   ("warp PC stepped +1", ws.WARP_PC[wut], pc_before + 16'd1);

        // =====================================================================
        // T2: scattered STORE then LOAD (each lane in its own block)
        //      -> 16 transactions each (coalescing degrades gracefully).
        // =====================================================================
        $display("\n==== T2: scattered STORE + LOAD (16 blocks) ====");
        for (k = 0; k < 16; k = k + 1) begin
            addr_in[k] = k[15:0] * 16;          // block k, word 0
            sw_out[k]  = 16'hB000 + k[15:0];
        end
        active_mask = 16'hFFFF;
        fire_request(1'b0);                    // STORE
        check_int("T2 store transactions", last_xact_count, 16);

        for (k = 0; k < 16; k = k + 1) addr_in[k] = k[15:0] * 16;
        active_mask = 16'hFFFF;
        fire_request(1'b1);                    // LOAD
        check_int("T2 load transactions", last_xact_count, 16);
        for (k = 0; k < 16; k = k + 1) chk_lw(k, 16'hB000 + k[15:0]);
        $display("  (16 scattered lane values verified against B000..B00F)");

        // =====================================================================
        // T3: partial-mask STORE (lanes 0..7) into a fresh block, full LOAD.
        //      Masked-out words must remain untouched (0).
        // =====================================================================
        $display("\n==== T3: partial-mask STORE (lanes 0..7), full LOAD ====");
        for (k = 0; k < 16; k = k + 1) begin
            addr_in[k] = 16'h0040 + k[15:0];   // block 4
            sw_out[k]  = 16'hC000 + k[15:0];
        end
        active_mask = 16'h00FF;                // only lanes 0..7
        fire_request(1'b0);                    // STORE
        check_int("T3 store transactions", last_xact_count, 1);

        for (k = 0; k < 16; k = k + 1) addr_in[k] = 16'h0040 + k[15:0];
        active_mask = 16'hFFFF;
        fire_request(1'b1);                    // LOAD all 16
        check_int("T3 load transactions", last_xact_count, 1);
        for (k = 0; k < 8;  k = k + 1) chk_lw(k, 16'hC000 + k[15:0]); // written
        for (k = 8; k < 16; k = k + 1) chk_lw(k, 16'h0000);          // untouched
        $display("  (lanes 0..7 = C000.., lanes 8..15 = 0000 verified)");

        // settle, confirm every warp is runnable again before halting
        run_cycles(3);
        $display("\n==== pre-halt: no warp left stalled ====");
        check_int("WARP_STALL[0]", ws.WARP_STALL[0], 0);
        check_int("WARP_STALL[1]", ws.WARP_STALL[1], 0);
        check_int("WARP_STALL[2]", ws.WARP_STALL[2], 0);
        check_int("WARP_STALL[3]", ws.WARP_STALL[3], 0);

        // =====================================================================
        // T4: HALT each warp in turn; done asserts once all are finished.
        // =====================================================================
        $display("\n==== T4: HALT retires warps; done asserts when all finish ====");
        for (k = 0; k < 4; k = k + 1) begin
            @(negedge clk);
            wut  = ws_current_warp_id;
            halt = 1'b1;
            @(negedge clk);                    // WS retires wut, -> SWITCH
            halt = 1'b0;
            @(negedge clk);                    // WS switches to next runnable
            @(negedge clk);
            check_int("warp finished", ws.WARP_FINISHED[wut], 1);
        end
        check_int("done after 4 halts", ws_done, 1);

        // ---- summary ----
        $display("\n=====================================================");
        $display(" TESTS: %0d   FAILURES: %0d   ->  %s",
                 tests, errors, (errors == 0) ? "ALL PASS" : "FAILURES PRESENT");
        $display("=====================================================\n");
        $finish;
    end

    // safety timeout
    initial begin
        #50000;
        $display("TIMEOUT -- simulation did not finish");
        $finish;
    end

endmodule