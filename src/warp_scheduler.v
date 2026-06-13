// ============================================================================
//  warp_scheduler  (pure Verilog, no SystemVerilog enum/logic/always_ff)
// ----------------------------------------------------------------------------
//  Aligned to the coalescing memory_scheduler handshake:
//
//    * The WS presents one warp per cycle: warp_id_to_ms = current_warp,
//      together with that warp's PC (warp_ready) and active mask
//      (warp_ready_mask).
//
//    * When the datapath/top decodes a memory instruction for the active warp
//      it asserts mem_req for ONE cycle. On that same cycle:
//          - the memory_scheduler latches the request, tagging it with
//            warp_id_from_ws ( == warp_id_to_ms == current_warp ), and
//          - the warp_scheduler marks the active warp stalled and round-robins
//            to the next runnable warp.
//
//    * When the memory_scheduler finishes a warp it pulses mem_done for one
//      cycle together with warp_id_to_ws ( -> warp_id_from_ms here ). The WS
//      clears that warp's stall and steps its PC past the memory instruction.
//
//    * When the active warp reaches HALT, top asserts halt for one cycle; the
//      WS marks the warp finished and switches away permanently. done asserts
//      once every warp is finished.
//
//  Note: the PC initialisation below is written for NUMBER_OF_WARPS = 4 (one
//  warp every 16 instructions), matching the original design and the 2-bit
//  warp-id ports shared with the memory_scheduler.
// ============================================================================
// ============================================================================
//  warp_scheduler  (pure Verilog) -- the doc-3 coalescing-aligned scheduler,
//  EXTENDED for an executing core:
//     + running   : 1 only in the RUN state (a real instruction commits this
//                   cycle).  The 1-cycle SWITCH after a stall/halt is a bubble.
//     + redirect/pc_target : branch / jump next-PC for the current warp.
//  Memory handshake (mem_req/mem_done/warp ids) is UNCHANGED from doc 3.
// ============================================================================
module warp_scheduler #(
    parameter NUMBER_OF_WARPS = 4
) (
    input             clk,
    input             rst,
    input             mem_req,         // memory instruction issuing this cycle
    input             mem_done,        // from memory_scheduler
    input      [1:0]  warp_id_from_ms, // from memory_scheduler (its warp_id_to_ws)
    input             halt,            // current warp hit HALT
    input             hold,            // mem op pending but scheduler busy: freeze warp
    input             redirect,        // branch/jump taken for current warp
    input      [15:0] pc_target,       // redirect target PC

    output     [1:0]  warp_id_to_ms,
    output     [15:0] warp_ready,
    output     [15:0] warp_ready_mask,
    output     [1:0]  current_warp_id,
    output            running,         // high in RUN (commit cycle)
    output            done             // all warps finished
);
    reg [15:0] WARP_PC       [0:NUMBER_OF_WARPS-1];
    reg [15:0] WARP_MASK     [0:NUMBER_OF_WARPS-1];
    reg        WARP_STALL    [0:NUMBER_OF_WARPS-1];
    reg        WARP_FINISHED [0:NUMBER_OF_WARPS-1];
    reg [1:0]  current_warp;

    localparam RUN = 1'b0, SWITCH = 1'b1;
    reg state_curr;

    integer i;
    reg [1:0] next_warp;
    reg       next_found;
    integer   off, cand;

    assign warp_id_to_ms   = current_warp;
    assign current_warp_id = current_warp;
    assign warp_ready      = WARP_PC[current_warp];
    assign warp_ready_mask = WARP_MASK[current_warp];
    assign running         = (state_curr == RUN);
    assign done = WARP_FINISHED[0] & WARP_FINISHED[1] &
                  WARP_FINISHED[2] & WARP_FINISHED[3];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < NUMBER_OF_WARPS; i = i + 1) begin
                WARP_STALL[i]    <= 1'b0;
                WARP_FINISHED[i] <= 1'b0;
                WARP_MASK[i]     <= 16'hFFFF;
            end
            WARP_PC[0] <= 16'h0000;
            WARP_PC[1] <= 16'h0010;
            WARP_PC[2] <= 16'h0020;
            WARP_PC[3] <= 16'h0030;
            current_warp <= 2'b00;
            state_curr   <= RUN;
        end
        else begin
            // (A) memory completion: clear stall + step PC past the mem inst.
            if (mem_done) begin
                WARP_STALL[warp_id_from_ms] <= 1'b0;
                WARP_PC[warp_id_from_ms]    <= WARP_PC[warp_id_from_ms] + 16'd1;
            end

            // (B) scheduling FSM
            case (state_curr)
                RUN: begin
                    if (mem_req) begin
                        WARP_STALL[current_warp] <= 1'b1;
                        state_curr               <= SWITCH;
                    end
                    else if (halt) begin
                        WARP_FINISHED[current_warp] <= 1'b1;
                        state_curr                  <= SWITCH;
                    end
                    else if (hold) begin
                        // memory op waiting for the scheduler: hold PC, no commit
                    end
                    else begin
                        WARP_PC[current_warp] <=
                            redirect ? pc_target : (WARP_PC[current_warp] + 16'd1);
                    end
                end
                SWITCH: begin
                    next_found = 1'b0;
                    next_warp  = current_warp;
                    for (off = 1; off <= NUMBER_OF_WARPS; off = off + 1) begin
                        cand = (current_warp + off) % NUMBER_OF_WARPS;
                        if (!next_found && !WARP_STALL[cand] && !WARP_FINISHED[cand]) begin
                            next_found = 1'b1;
                            next_warp  = cand[1:0];
                        end
                    end
                    if (next_found) begin
                        current_warp <= next_warp;
                        state_curr   <= RUN;
                    end
                end
                default: state_curr <= RUN;
            endcase
        end
    end
endmodule