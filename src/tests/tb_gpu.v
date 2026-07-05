`timescale 1ns/1ps

module tb_gpu;

    localparam NUMBER_OF_WARPS = 4;
    localparam WARP_BITS       = 2;
    localparam LINE_WORDS      = 16;
    localparam OFFSET_BITS     = 4;
    localparam ADDR_WIDTH      = 12;

    localparam [3:0] OP_LOAD  = 4'b0110;
    localparam [3:0] OP_STORE = 4'b0010;

    reg clk;
    reg rst;

    // ---------------- signals between "decode" (stimulus) and warp_scheduler ----------------
    reg  mem_req_stim;
    reg  halt_stim;
    reg  hold_stim;
    reg  redirect_stim;
    reg  [15:0] pc_target_stim;

    wire [WARP_BITS-1:0] warp_id_to_ms;
    wire [15:0]          warp_ready;
    wire [15:0]          warp_ready_mask;
    wire [WARP_BITS-1:0] current_warp_id;
    wire                 running;
    wire                 done;

    // returned from memory_scheduler back into warp_scheduler
    wire                 mem_done_w;
    wire [WARP_BITS-1:0] warp_id_from_ms_w;

    warp_scheduler #(
        .NUMBER_OF_WARPS(NUMBER_OF_WARPS),
        .WARP_BITS(WARP_BITS)
    ) ws (
        .clk(clk),
        .rst(rst),
        .mem_req(mem_req_stim),
        .mem_done(mem_done_w),
        .warp_id_from_ms(warp_id_from_ms_w),
        .halt(halt_stim),
        .hold(hold_stim),
        .redirect(redirect_stim),
        .pc_target(pc_target_stim),
        .warp_id_to_ms(warp_id_to_ms),
        .warp_ready(warp_ready),
        .warp_ready_mask(warp_ready_mask),
        .current_warp_id(current_warp_id),
        .running(running),
        .done(done)
    );

    // ---------------- memory_scheduler stimulus / wiring ----------------
    reg  [3:0]  request_stim;
    reg  [15:0] active_mask_stim;
    reg  [15:0] addr_in_stim [0:15];
    reg  [31:0] sw_out_stim  [0:15];
    reg  [3:0]  lw_destination_stim;

    wire [31:0] lw_out_w [0:15];
    wire        stall_w;
    wire        mem_write_w;
    wire [3:0]  lw_destination_out_w;

    wire [15:0] addr_out_w;
    wire [31:0] sw_line_out_w [0:LINE_WORDS-1];
    wire [LINE_WORDS-1:0] sw_word_mask_w;
    wire [31:0] lw_line_in_w [0:LINE_WORDS-1];

    wire [1:0] lw_warp_id_w;
    wire       lw_ready_w;

    // See NOTE above ms instantiation: selects the warp-id tag fed into
    // memory_scheduler's warp_id_from_ws port. phase45_active/phase45_warp_id
    // are declared further below with the rest of the phase 4/5 stimulus
    // registers; Verilog module-item declaration order doesn't matter here.
    wire [1:0] warp_id_from_ws_mux = phase45_active ? phase45_warp_id : warp_id_to_ms;

    memory_scheduler #(
        .LINE_WORDS(LINE_WORDS),
        .OFFSET_BITS(OFFSET_BITS)
    ) ms (
        .clk(clk),
        .reset(rst),
        .request(request_stim),
        .active_mask(active_mask_stim),
        .addr_in(addr_in_stim),
        .sw_out(sw_out_stim),
        .lw_out(lw_out_w),
        .stall(stall_w),
        .mem_write(mem_write_w),

        // NOTE on cross-wiring: warp_scheduler tags every request it issues
        // with the warp that issued it (warp_id_to_ms) -> memory_scheduler's
        // warp_id_from_ws. memory_scheduler in turn reports which warp's
        // request just completed (warp_id_to_ws) -> warp_scheduler's
        // warp_id_from_ms, alongside the mem_done pulse.
        // During phase 4/5, memory_scheduler is driven directly (bypassing
        // warp_scheduler) so we can tag requests with an arbitrary warp id;
        // warp_id_from_ws_mux selects between the two sources.
        .mem_req(mem_req_stim),
        .warp_id_from_ws(warp_id_from_ws_mux),
        .mem_done(mem_done_w),
        .warp_id_to_ws(warp_id_from_ms_w),
        .lw_destination(lw_destination_stim),
        .lw_destination_out(lw_destination_out_w),

        .lw_line_in(lw_line_in_w),
        .addr_out(addr_out_w),
        .sw_line_out(sw_line_out_w),
        .sw_word_mask(sw_word_mask_w),

        .lw_warp_id(lw_warp_id_w),
        .lw_ready(lw_ready_w)
    );

    data_memory_line #(
        .DATA_WIDTH(32),
        .LINE_WORDS(LINE_WORDS),
        .OFFSET_BITS(OFFSET_BITS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dml (
        .clk(clk),
        .mem_write(mem_write_w),
        .addr_base(addr_out_w[ADDR_WIDTH-1:OFFSET_BITS]),
        .sw_word_mask(sw_word_mask_w),
        .sw_line_out(sw_line_out_w),
        .lw_line_in(lw_line_in_w)
    );

    // ---------------- clock ----------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Minimal "decode" stage (stands in for an instruction memory / decode
    // unit, which isn't part of the DUT). Program, per warp, relative to
    // that warp's base PC (base = warp_id * 16, matching the scheduler's
    // reset values):
    //
    //   base+0 .. +1 : ordinary instructions (PC just increments)
    //   base+2       : STORE  16 words, one per lane, to addr = base+lane
    //   base+3 .. +4 : ordinary instructions
    //   base+5       : LOAD   the same 16 words back
    //   base+6 .. +7 : ordinary instructions
    //   base+8       : HALT
    //
    // This exercises: round-robin switching, the mem_req/stall/mem_done
    // handshake with memory_scheduler, coalesced store+load through
    // data_memory_line, and the halt/done path.
    // ------------------------------------------------------------------
    reg [15:0] base;
    integer w;

    // Phase 2 (coalescing test) takes direct manual control of the
    // memory_scheduler inputs; when active, this "decode" stage goes quiet.
    reg        phase2_active;
    reg        mem_req_phase2;
    reg [3:0]  phase2_request_type;
    reg [15:0] phase2_addr [0:15];
    reg [31:0] phase2_data [0:15];

    // Phase 3 (redirect/hold test) takes direct manual control of
    // warp_scheduler's decode-side inputs only (mem_req/halt held low,
    // memory_scheduler is unused/idle during this phase).
    reg        phase3_active;
    reg        phase3_hold;
    reg        phase3_redirect;
    reg [15:0] phase3_pc_target;

    // Phase 4 / 5 (backpressure + partial-mask tests) drive
    // memory_scheduler directly, same pattern as phase 2, but with their
    // own per-slot address/data/mask arrays and an explicit warp tag
    // (since we need to enqueue requests "as" specific warps without
    // routing them through warp_scheduler at all).
    reg        phase45_active;
    reg        mem_req_phase45;
    reg [3:0]  phase45_request_type;
    reg [1:0]  phase45_warp_id;
    reg [15:0] phase45_mask;
    reg [15:0] phase45_addr [0:15];
    reg [31:0] phase45_data [0:15];
    reg [3:0]  phase45_dst;

    always @(*) begin
        mem_req_stim        = 1'b0;
        halt_stim           = 1'b0;
        hold_stim           = 1'b0;
        redirect_stim       = 1'b0;
        pc_target_stim      = 16'h0000;
        request_stim        = OP_LOAD;
        active_mask_stim    = 16'hFFFF;
        lw_destination_stim = {2'b00, current_warp_id};

        base = current_warp_id * 16;

        for (w = 0; w < 16; w = w + 1) begin
            addr_in_stim[w] = base + w[3:0];
            sw_out_stim[w]  = (current_warp_id * 100) + w + 1; // arbitrary distinct pattern
        end

        if (phase3_active) begin
            // ---- Phase 3: direct redirect/hold(/halt) control of
            // warp_scheduler ----
            // mem_req stays low throughout; hold/redirect/pc_target are
            // driven straight from the testbench so we can observe
            // warp_ready (PC) responding to exactly those signals with
            // nothing else (mem ops) in the mix. phase3_halt is used only
            // at the very end, to force every warp to WARP_FINISHED=1 (so
            // Phase 4/5 can drive memory_scheduler directly without
            // warp_scheduler's own mem_req branch reacting to the shared
            // mem_req_stim wire -- see note by the ms instantiation).
            hold_stim      = phase3_hold;
            redirect_stim  = phase3_redirect;
            pc_target_stim = phase3_pc_target;
            halt_stim      = phase3_halt;
        end else if (phase45_active) begin
            // ---- Phase 4/5: direct control of memory_scheduler, tagging
            // requests with an explicit warp id (warp_id_from_ws), bypassing
            // warp_scheduler entirely so we can shape queue-fill and
            // partial-active-mask scenarios precisely.
            mem_req_stim         = mem_req_phase45;
            request_stim         = phase45_request_type;
            active_mask_stim     = phase45_mask;
            lw_destination_stim  = phase45_dst;
            for (w = 0; w < 16; w = w + 1) begin
                addr_in_stim[w] = phase45_addr[w];
                sw_out_stim[w]  = phase45_data[w];
            end
        end else if (!phase2_active) begin
            if (running) begin
                if (warp_ready == base + 16'd2) begin
                    mem_req_stim = 1'b1;
                    request_stim = OP_STORE;
                end else if (warp_ready == base + 16'd5) begin
                    mem_req_stim = 1'b1;
                    request_stim = OP_LOAD;
                end else if (warp_ready == base + 16'd8) begin
                    halt_stim = 1'b1;
                end
            end
        end else begin
            // ---- Phase 2: explicit multi-segment (non-coalesced) access ----
            // Lanes 0-7 target one 16-word memory line, lanes 8-15 target the
            // *next* line, so memory_scheduler's leader-election loop in the
            // REQ state must run twice per request instead of once.
            mem_req_stim         = mem_req_phase2;
            request_stim         = phase2_request_type;
            active_mask_stim     = 16'hFFFF;
            lw_destination_stim  = 4'hE;
            for (w = 0; w < 16; w = w + 1) begin
                addr_in_stim[w] = phase2_addr[w];
                sw_out_stim[w]  = phase2_data[w];
            end
        end
    end

    // ------------------------------------------------------------------
    // Instrument memory_scheduler internally to count how many separate
    // coalesced memory-line blocks it dispatches per request. Every block
    // dispatch causes exactly one REQ -> WAIT transition, so counting
    // entries into WAIT counts blocks. This is only meaningful because
    // Phase 2 runs after Phase 1 is fully drained (no other request is
    // in flight to confound the count).
    // ------------------------------------------------------------------
    localparam [2:0] TB_MS_WAIT = 3'b100;
    reg [2:0] ms_state_prev;
    integer   block_dispatch_count;

    always @(posedge clk) begin
        if (rst)
            ms_state_prev <= 3'b000;
        else
            ms_state_prev <= ms.state_curr;
    end

    wire ms_entering_wait = (ms.state_curr == TB_MS_WAIT) && (ms_state_prev != TB_MS_WAIT);

    always @(posedge clk) begin
        if (rst)
            block_dispatch_count <= 0;
        else if (ms_entering_wait)
            block_dispatch_count <= block_dispatch_count + 1;
    end

    // ------------------------------------------------------------------
    // Scoreboard: remember what each warp stored so we can check the
    // matching load result later.
    //
    // FIX (bug #2): this block used to run unconditionally for the whole
    // simulation and always indexed by current_warp_id / relied on the
    // "decode" stage's mem_req_stim & request_stim. During Phase 4/5,
    // requests are tagged with phase45_warp_id (via warp_id_from_ws_mux),
    // NOT current_warp_id (which is frozen/stale once warp_scheduler is
    // halted), and are driven by mem_req_phase45/phase45_request_type,
    // NOT mem_req_stim/request_stim in the "decode" sense. Indexing by
    // current_warp_id during phase45 silently wrote into (and later read
    // from) the wrong scoreboard slot, corrupting comparisons against
    // stale data from earlier phases. Phase 4/5 already have their own
    // dedicated expected_p4/expected_p5 checks, so this generic
    // scoreboard should simply stay inactive during phase2/3/45 and only
    // arbitrate Phase 1 (round-robin) traffic.
    // ------------------------------------------------------------------
    reg [31:0] expected [0:NUMBER_OF_WARPS-1][0:15];
    integer errors;
    integer loads_checked;

    // lw_ready is a level signal in memory_scheduler (held across cycles
    // until the *next* transaction reaches REQ_CHECK), not a one-cycle
    // pulse, so the scoreboard must qualify on its rising edge only.
    reg lw_ready_prev;
    wire lw_ready_edge = lw_ready_w && !lw_ready_prev;

    always @(posedge clk) begin
        if (rst)
            lw_ready_prev <= 1'b0;
        else
            lw_ready_prev <= lw_ready_w;
    end

    always @(posedge clk) begin
        if (rst) begin
            errors        <= 0;
            loads_checked <= 0;
        end else begin
            // FIX: only arbitrate the generic scoreboard during Phase 1,
            // when current_warp_id / mem_req_stim / request_stim genuinely
            // reflect the "decode" stage's own traffic.
            if (!phase2_active && !phase3_active && !phase45_active) begin
                if (mem_req_stim && request_stim == OP_STORE) begin
                    for (w = 0; w < 16; w = w + 1)
                        expected[current_warp_id][w] <= sw_out_stim[w];
                end

                if (lw_ready_edge) begin
                    loads_checked <= loads_checked + 1;
                    for (w = 0; w < 16; w = w + 1) begin
                        if (lw_out_w[w] !== expected[lw_warp_id_w][w]) begin
                            errors <= errors + 1;
                            $display("[FAIL] t=%0t warp=%0d lane=%0d expected=%0d got=%0d",
                                      $time, lw_warp_id_w, w, expected[lw_warp_id_w][w], lw_out_w[w]);
                        end
                    end
                    $display("[INFO] t=%0t load result captured for warp %0d", $time, lw_warp_id_w);
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Trace
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst)
            $display("t=%0t | warp=%0d pc=%0d running=%b | mem_req=%b req_type=%b stall=%b | mem_done=%b done_warp=%0d | all_done=%b",
                       $time, current_warp_id, warp_ready, running,
                       mem_req_stim, request_stim, stall_w,
                       mem_done_w, warp_id_from_ms_w, done);
    end

    // ------------------------------------------------------------------
    // Main stimulus / timeout / pass-fail report
    // ------------------------------------------------------------------
    integer cyc;
    integer block_count_before, blocks_this_request;
    reg [31:0] expected_phase2 [0:15];
    reg [15:0] coalesce_base;

    // Phase 3 (redirect/hold)
    reg [15:0] pc_hold_before;
    reg [15:0] pc_redirect_target;
    reg        phase3_halt;
    integer    drain_cyc;

    // Phase 4 (queue backpressure)
    integer qi;
    reg [15:0] p4_addr_5th [0:15];
    reg [31:0] p4_data_5th [0:15];
    reg [15:0] p4_addr_6th [0:15];
    reg [31:0] p4_data_6th [0:15];
    reg [31:0] expected_p4 [0:15];

    // Phase 5 (partial active_mask coalescing)
    reg [31:0] expected_p5 [0:15];

    initial begin
        rst = 1;
        cyc = 0;
        phase2_active  = 1'b0;
        mem_req_phase2 = 1'b0;
        phase3_active   = 1'b0;
        phase3_hold     = 1'b0;
        phase3_redirect = 1'b0;
        phase45_active  = 1'b0;
        mem_req_phase45 = 1'b0;
        repeat (3) @(posedge clk);
        rst = 0;

        // ================= Phase 1: round robin + single-block coalescing =================
        while (!done && cyc < 3000) begin
            @(posedge clk);
            cyc = cyc + 1;
        end

        $display("--------------------------------------------------");
        $display("Phase 1 (round robin + fully-coalesced store/load)");
        if (!done) begin
            errors = errors + 1;
            $display("[FAIL] Timed out after %0d cycles without 'done'", cyc);
        end else begin
            $display("[INFO] All warps finished (done=1) after %0d cycles", cyc);
            $display("[INFO] Loads checked: %0d (expect %0d = one per warp)",
                       loads_checked, NUMBER_OF_WARPS);
            if (loads_checked != NUMBER_OF_WARPS) begin
                errors = errors + 1;
                $display("[FAIL] Unexpected number of completed loads");
            end
        end

        // ================= Phase 2: multi-segment coalescing test =================
        // 16 lanes, but split across two 16-word memory lines (8 lanes each),
        // well away from the address range Phase 1 used (0..63), so this
        // request must be serviced as two separate coalesced blocks.
        $display("--------------------------------------------------");
        $display("Phase 2 (explicit multi-line coalescing test)");

        phase2_active = 1'b1;
        coalesce_base = 16'd512;

        for (w = 0; w < 8; w = w + 1) begin
            phase2_addr[w] = coalesce_base + w[3:0];           // line A
            phase2_data[w] = 32'h1000 + w;
        end
        for (w = 8; w < 16; w = w + 1) begin
            phase2_addr[w] = coalesce_base + 16 + (w[3:0] - 8); // line B
            phase2_data[w] = 32'h2000 + w;
        end
        for (w = 0; w < 16; w = w + 1)
            expected_phase2[w] = phase2_data[w];

        // ---- STORE split across the two lines ----
        @(posedge clk);
        #1; // FIX (bug #1): let NBA updates from this edge settle before sampling
        block_count_before   = block_dispatch_count;
        phase2_request_type  = OP_STORE;
        mem_req_phase2       = 1'b1;
        @(posedge clk);
        mem_req_phase2       = 1'b0;

        wait (mem_done_w == 1'b1);
        @(posedge clk);
        #1; // FIX: settle before reading block_dispatch_count
        blocks_this_request = block_dispatch_count - block_count_before;
        $display("[INFO] STORE dispatched %0d coalesced block(s) (expected 2)", blocks_this_request);
        if (blocks_this_request != 2) begin
            errors = errors + 1;
            $display("[FAIL] STORE did not split into two separate memory-line blocks");
        end

        repeat (2) @(posedge clk); // let memory_scheduler settle back to IDLE

        // ---- LOAD the same split addresses back ----
        #1; // FIX: settle before reading block_dispatch_count
        block_count_before   = block_dispatch_count;
        phase2_request_type  = OP_LOAD;
        mem_req_phase2       = 1'b1;
        @(posedge clk);
        mem_req_phase2       = 1'b0;

        wait (lw_ready_edge == 1'b1);
        for (w = 0; w < 16; w = w + 1) begin
            if (lw_out_w[w] !== expected_phase2[w]) begin
                errors = errors + 1;
                $display("[FAIL] Phase2 lane %0d mismatch: expected %0d got %0d",
                           w, expected_phase2[w], lw_out_w[w]);
            end
        end
        @(posedge clk);
        #1; // FIX: settle before reading block_dispatch_count
        blocks_this_request = block_dispatch_count - block_count_before;
        $display("[INFO] LOAD dispatched %0d coalesced block(s) (expected 2)", blocks_this_request);
        if (blocks_this_request != 2) begin
            errors = errors + 1;
            $display("[FAIL] LOAD did not split into two separate memory-line blocks");
        end

        phase2_active = 1'b0;

        // ================= Phase 3: redirect / hold =================
        // warp_scheduler only, mem_req/halt held low throughout. Phase 1/2
        // already ran every warp to completion, so give everything a fresh
        // reset (also clears memory_scheduler/data_memory, unused here) and
        // drive warp 0 directly via hold/redirect with nothing else in play.
        $display("--------------------------------------------------");
        $display("Phase 3 (redirect + hold control of warp_scheduler)");

        rst             = 1'b1;
        phase3_active   = 1'b1;
        phase3_hold     = 1'b0;
        phase3_redirect = 1'b0;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); // first live RUN cycle: warp 0, PC increments normally
        #1; // FIX: settle before reading warp_ready

        // ---- HOLD: PC must not move while hold is asserted ----
        pc_hold_before = warp_ready;
        phase3_hold    = 1'b1;
        repeat (4) @(posedge clk);
        #1; // FIX: settle before reading warp_ready
        if (warp_ready !== pc_hold_before) begin
            errors = errors + 1;
            $display("[FAIL] hold: PC changed from %0d to %0d while hold was asserted",
                       pc_hold_before, warp_ready);
        end else
            $display("[INFO] hold: PC correctly held at %0d across 4 cycles", warp_ready);

        phase3_hold = 1'b0;
        @(posedge clk); // hold released: PC should resume normal increment
        #1; // FIX: settle before reading warp_ready
        if (warp_ready !== pc_hold_before + 16'd1) begin
            errors = errors + 1;
            $display("[FAIL] hold: PC did not resume incrementing after release (got %0d, expected %0d)",
                       warp_ready, pc_hold_before + 16'd1);
        end else
            $display("[INFO] hold: PC resumed normal increment to %0d after release", warp_ready);

        // ---- REDIRECT: PC must jump to pc_target the next cycle, then
        // resume normal incrementing from there ----
        pc_redirect_target = 16'h0234;
        phase3_redirect     = 1'b1;
        phase3_pc_target    = pc_redirect_target;
        @(posedge clk);
        phase3_redirect     = 1'b0;
        #1; // FIX: settle before reading warp_ready
        if (warp_ready !== pc_redirect_target) begin
            errors = errors + 1;
            $display("[FAIL] redirect: PC did not jump to target 0x%0h (got 0x%0h)",
                       pc_redirect_target, warp_ready);
        end else
            $display("[INFO] redirect: PC correctly jumped to target 0x%0h", warp_ready);

        @(posedge clk);
        #1; // FIX: settle before reading warp_ready
        if (warp_ready !== pc_redirect_target + 16'd1) begin
            errors = errors + 1;
            $display("[FAIL] redirect: PC did not resume normal increment after redirect (got 0x%0h, expected 0x%0h)",
                       warp_ready, pc_redirect_target + 16'd1);
        end else
            $display("[INFO] redirect: PC resumed normal increment to 0x%0h after redirect", warp_ready);

        // ---- Drain warp_scheduler to "done" (no reset) before Phase 4/5 ----
        // mem_req_stim fans out to warp_scheduler as well as
        // memory_scheduler (real hardware wiring, see NOTE by the ms
        // instantiation). Phase 4/5 drive memory_scheduler directly via
        // mem_req_stim, so unless every warp is already WARP_FINISHED,
        // warp_scheduler's own mem_req branch would react to that same
        // wire and interfere. Force every warp to finish via halt (no
        // global reset -- that would also re-empty an already-clean
        // memory_scheduler queue, which is fine, but would undo this
        // "all finished" property we're establishing right now, so do
        // this immediately before, not after, dropping into phase45).
        phase3_halt = 1'b1;
        for (drain_cyc = 0; drain_cyc < 12 && !done; drain_cyc = drain_cyc + 1)
            @(posedge clk);
        phase3_halt = 1'b0;
        if (!done) begin
            errors = errors + 1;
            $display("[FAIL] could not drain warp_scheduler to done before Phase 4/5");
        end
        phase3_active = 1'b0;

        // ================= Phase 4: memory_scheduler queue backpressure =================
        // warp_scheduler is now fully done (see drain step above), so its
        // mem_req branch is structurally unreachable regardless of what we
        // do with mem_req_stim from here on -- safe to drive
        // memory_scheduler directly. Fill all 4 slots with requests tagged
        // to 4 distinct (synthetic) warp ids, each one deliberately
        // scattered across 16 separate memory lines (one active lane per
        // line) so each takes ~16 coalesce iterations to drain -- giving a
        // wide, deterministic window where the queue is provably full,
        // instead of racing a fast single-block drain.
        $display("--------------------------------------------------");
        $display("Phase 4 (memory_scheduler queue backpressure)");

        phase45_active  = 1'b1;
        mem_req_phase45 = 1'b0;

        for (qi = 0; qi < 4; qi = qi + 1) begin
            phase45_warp_id      = qi[1:0];
            phase45_request_type = OP_STORE;
            phase45_mask         = 16'hFFFF;
            phase45_dst          = 4'h0;
            for (w = 0; w < 16; w = w + 1) begin
                // qi*8192 keeps each warp's 16 lines from ever aliasing
                // with another warp's; w*256 spreads this warp's own 16
                // lanes across 16 different lines (one lane each).
                phase45_addr[w] = (qi * 8192) + (w * 256);
                phase45_data[w] = (qi * 1000) + w;
            end
            mem_req_phase45 = 1'b1;
            @(posedge clk);
            mem_req_phase45 = 1'b0;
            @(posedge clk); // enqueued into slot `qi` by now (queue not yet full for qi<3)
        end

        #1; // FIX: settle before reading stall_w (combinational off OCCUPIED, low risk but consistent)
        if (!stall_w) begin
            errors = errors + 1;
            $display("[FAIL] backpressure: stall not asserted with all 4 queue slots occupied");
        end else
            $display("[INFO] backpressure: stall correctly asserted with queue full");

        // ---- 5th request: issued while stall/queue_full is asserted.
        // A single overlapping request should still latch into req_pending
        // (the latch condition is mem_req && !req_pending, independent of
        // queue_full) and wait there safely until a slot frees. ----
        for (w = 0; w < 16; w = w + 1) begin
            p4_addr_5th[w] = 16'd40000 + w;      // well clear of the 4 filler regions
            p4_data_5th[w] = 32'h5000 + w;
            expected_p4[w] = p4_data_5th[w];
        end
        phase45_warp_id      = 2'b01;
        phase45_request_type = OP_STORE;
        phase45_mask         = 16'hFFFF;
        for (w = 0; w < 16; w = w + 1) begin
            phase45_addr[w] = p4_addr_5th[w];
            phase45_data[w] = p4_data_5th[w];
        end
        mem_req_phase45 = 1'b1;
        @(posedge clk);
        mem_req_phase45 = 1'b0;
        @(posedge clk);
        #1; // FIX: settle before reading ms.req_pending

        if (ms.req_pending !== 1'b1) begin
            errors = errors + 1;
            $display("[FAIL] backpressure: 5th request did not latch into req_pending while queue was full");
        end else
            $display("[INFO] backpressure: 5th request correctly latched into req_pending, waiting for a free slot");

        // ---- 6th request: issued WHILE the 5th is still latched
        // (req_pending==1) and the queue is still full. The latch
        // condition (mem_req && !req_pending) blocks this one entirely --
        // demonstrating that an issuer which doesn't itself respect
        // `stall` can silently lose a request here. warp_scheduler has no
        // `stall` input at all, so in the full integrated system this is a
        // real, reachable risk (not just a corner case), not merely a
        // theoretical one. ----
        for (w = 0; w < 16; w = w + 1) begin
            p4_addr_6th[w] = 16'd41000 + w;
            p4_data_6th[w] = 32'h6000 + w;
        end
        phase45_warp_id      = 2'b10;
        phase45_request_type = OP_STORE;
        for (w = 0; w < 16; w = w + 1) begin
            phase45_addr[w] = p4_addr_6th[w];
            phase45_data[w] = p4_data_6th[w];
        end
        mem_req_phase45 = 1'b1;
        @(posedge clk);
        mem_req_phase45 = 1'b0;
        @(posedge clk);
        #1; // FIX: settle before reading ms.req_warp / ms.req_addr

        if (ms.req_warp !== 2'b01 || ms.req_addr[0] !== p4_addr_5th[0]) begin
            errors = errors + 1;
            $display("[FAIL] backpressure: latch was overwritten by the 6th request (should still hold the 5th's data)");
        end else
            $display("[INFO] backpressure: confirmed -- 6th request's mem_req was silently dropped (latch still holds the 5th's data), demonstrating the dropped-request risk");

        // ---- Let the 4 filler requests AND the 5th's store fully drain
        // (occupied_any low means every queue slot -- including whichever
        // one the 5th eventually landed in -- has completed), then confirm
        // its data by re-issuing the same addresses as a LOAD and checking
        // lw_out. Waiting for full drain (rather than just stall_w==0)
        // avoids a read-before-write race against the 5th's own store,
        // which may land in an earlier-scanned slot than expected.
        wait (ms.occupied_any == 1'b0);
        phase45_warp_id      = 2'b01;
        phase45_request_type = OP_LOAD;
        for (w = 0; w < 16; w = w + 1)
            phase45_addr[w] = p4_addr_5th[w];
        mem_req_phase45 = 1'b1;
        @(posedge clk);
        mem_req_phase45 = 1'b0;

        wait (lw_ready_edge == 1'b1);
        for (w = 0; w < 16; w = w + 1) begin
            if (lw_out_w[w] !== expected_p4[w]) begin
                errors = errors + 1;
                $display("[FAIL] backpressure: 5th request lane %0d expected=%0d got=%0d",
                           w, expected_p4[w], lw_out_w[w]);
            end
        end
        $display("[INFO] backpressure: 5th request drained and read back correctly once a slot freed");

        // FIX: Phase 4's final load-back only waited on lw_ready_edge, not
        // on mem_done_w. mem_done for that same request fires one cycle
        // later (DONE state, after lw_ready already pulsed in REQ). Without
        // draining that trailing mem_done pulse here, Phase 5's first
        // `wait (mem_done_w == 1'b1)` immediately catches this *stale*
        // pulse instead of its own request's completion, causing the block
        // counter delta to be sampled too early (reporting 0 dispatched
        // blocks for a request that hasn't even started yet) and throwing
        // off the following count as a side effect.
        wait (mem_done_w == 1'b1);
        @(posedge clk);

        // ================= Phase 5: partial active_mask coalescing =================
        // Everything so far used active_mask = 16'hFFFF. Here some lanes are
        // disabled, both for a single-line request (leader-election must
        // skip the disabled lanes but still coalesce the rest into one
        // block) and for a two-line request (disabled lanes in both halves,
        // still exactly 2 blocks, correct data only on the lanes that were
        // actually active).
        $display("--------------------------------------------------");
        $display("Phase 5 (partial active_mask coalescing)");

        // ---- Single line, alternating lanes active (0,2,4,...,14) ----
        #1; // FIX: settle before reading block_dispatch_count
        block_count_before   = block_dispatch_count;
        phase45_warp_id      = 2'b11;
        phase45_request_type = OP_STORE;
        phase45_mask         = 16'b0101010101010101; // lanes 0,2,4,...,14
        for (w = 0; w < 16; w = w + 1) begin
            phase45_addr[w] = 16'd50000 + w;   // all 16 lanes in one line
            phase45_data[w] = 32'h7000 + w;
            expected_p5[w]  = phase45_data[w];
        end
        mem_req_phase45 = 1'b1;
        @(posedge clk);
        mem_req_phase45 = 1'b0;
        wait (mem_done_w == 1'b1);
        @(posedge clk);
        #1; // FIX: settle before reading block_dispatch_count
        blocks_this_request = block_dispatch_count - block_count_before;
        $display("[INFO] partial-mask single-line STORE dispatched %0d block(s) (expected 1)", blocks_this_request);
        if (blocks_this_request != 1) begin
            errors = errors + 1;
            $display("[FAIL] partial-mask single-line STORE should coalesce into exactly 1 block");
        end

        repeat (2) @(posedge clk);

        #1; // FIX: settle before reading block_dispatch_count
        block_count_before   = block_dispatch_count;
        phase45_request_type = OP_LOAD;
        mem_req_phase45 = 1'b1;
        @(posedge clk);
        mem_req_phase45 = 1'b0;
        wait (lw_ready_edge == 1'b1);
        for (w = 0; w < 16; w = w + 1) begin
            if (phase45_mask[w] && lw_out_w[w] !== expected_p5[w]) begin
                errors = errors + 1;
                $display("[FAIL] partial-mask single-line lane %0d expected=%0d got=%0d",
                           w, expected_p5[w], lw_out_w[w]);
            end
        end
        @(posedge clk);
        #1; // FIX: settle before reading block_dispatch_count
        blocks_this_request = block_dispatch_count - block_count_before;
        $display("[INFO] partial-mask single-line LOAD dispatched %0d block(s) (expected 1)", blocks_this_request);
        if (blocks_this_request != 1) begin
            errors = errors + 1;
            $display("[FAIL] partial-mask single-line LOAD should coalesce into exactly 1 block");
        end

        repeat (2) @(posedge clk);

        // ---- Two lines, only some lanes active in each half ----
        #1; // FIX: settle before reading block_dispatch_count
        block_count_before   = block_dispatch_count;
        phase45_mask         = 16'b1010_0000_0101_0101; // lanes 0,2,4,6 (line A) + 8,10,13,15 (line B)
        phase45_request_type = OP_STORE;
        for (w = 0; w < 8; w = w + 1) begin
            phase45_addr[w] = 16'd51200 + w[3:0];            // line A
            phase45_data[w] = 32'h8000 + w;
            expected_p5[w]  = phase45_data[w];
        end
        for (w = 8; w < 16; w = w + 1) begin
            phase45_addr[w] = 16'd51216 + (w[3:0] - 8);      // line B
            phase45_data[w] = 32'h9000 + w;
            expected_p5[w]  = phase45_data[w];
        end
        mem_req_phase45 = 1'b1;
        @(posedge clk);
        mem_req_phase45 = 1'b0;
        wait (mem_done_w == 1'b1);
        @(posedge clk);
        #1; // FIX: settle before reading block_dispatch_count
        blocks_this_request = block_dispatch_count - block_count_before;
        $display("[INFO] partial-mask two-line STORE dispatched %0d block(s) (expected 2)", blocks_this_request);
        if (blocks_this_request != 2) begin
            errors = errors + 1;
            $display("[FAIL] partial-mask two-line STORE should dispatch exactly 2 blocks");
        end

        repeat (2) @(posedge clk);

        #1; // FIX: settle before reading block_dispatch_count
        block_count_before   = block_dispatch_count;
        phase45_request_type = OP_LOAD;
        mem_req_phase45 = 1'b1;
        @(posedge clk);
        mem_req_phase45 = 1'b0;
        wait (lw_ready_edge == 1'b1);
        for (w = 0; w < 16; w = w + 1) begin
            if (phase45_mask[w] && lw_out_w[w] !== expected_p5[w]) begin
                errors = errors + 1;
                $display("[FAIL] partial-mask two-line lane %0d expected=%0d got=%0d",
                           w, expected_p5[w], lw_out_w[w]);
            end
        end
        @(posedge clk);
        #1; // FIX: settle before reading block_dispatch_count
        blocks_this_request = block_dispatch_count - block_count_before;
        $display("[INFO] partial-mask two-line LOAD dispatched %0d block(s) (expected 2)", blocks_this_request);
        if (blocks_this_request != 2) begin
            errors = errors + 1;
            $display("[FAIL] partial-mask two-line LOAD should dispatch exactly 2 blocks");
        end

        phase45_active = 1'b0;

        $display("--------------------------------------------------");
        if (errors == 0)
            $display("[PASS] ALL CHECKS PASSED (round robin, mem handshake, single/multi-line coalescing,");
        else
            $display("[FAIL] %0d total mismatch(es)/failure(s) detected across all phases", errors);
        $display("          redirect/hold, queue backpressure, and partial active_mask coalescing)");
        $display("--------------------------------------------------");
        $finish;
    end

endmodule