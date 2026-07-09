module warp_scheduler #(
    parameter NUMBER_OF_WARPS = 4,
    parameter WARP_BITS = 2
)(
    input                    clk,
    input                    rst,
    input                    mem_req,
    input                    mem_done,
    input  [WARP_BITS-1:0]   warp_id_from_ms,

    input                    halt,
    input                    hold,
    input                    redirect,
    input  [15:0]            pc_target,

    output [WARP_BITS-1:0]   warp_id_to_ms,
    output [15:0]            warp_ready,
    output [15:0]            warp_ready_mask,
    output [WARP_BITS-1:0]   current_warp_id,
    output                   running,
    output                   done
);

    //------------------------------------------------------------
    // Warp Context
    reg [15:0] WARP_PC       [0:NUMBER_OF_WARPS-1];
    reg [15:0] WARP_MASK     [0:NUMBER_OF_WARPS-1];
    reg        WARP_STALL    [0:NUMBER_OF_WARPS-1];
    reg        WARP_FINISHED [0:NUMBER_OF_WARPS-1];
    reg [WARP_BITS-1:0] current_warp;

    // FSM
    localparam RUN    = 1'b0;
    localparam SWITCH = 1'b1;
    reg state_curr;

    // Outputs
    assign warp_id_to_ms   = current_warp;
    assign current_warp_id = current_warp;
    assign warp_ready      = WARP_PC[current_warp];
    assign warp_ready_mask = WARP_MASK[current_warp];
    assign running = (state_curr == RUN);

    // FIX #1: "done" was hardcoded to exactly 4 warps (WARP_FINISHED[0..3]),
    // which silently breaks if NUMBER_OF_WARPS is changed. Reduce over the
    // actual parameter instead.
    reg done_r;
    integer d;
    always @(*) begin
        done_r = 1'b1;
        for (d = 0; d < NUMBER_OF_WARPS; d = d + 1)
            done_r = done_r & WARP_FINISHED[d];
    end
    assign done = done_r;

    // Next Warp Selection (Round Robin)
    reg                    next_found;
    reg [WARP_BITS-1:0]    next_warp;

    integer off;
    integer cand;

    always @(*) begin

        next_found = 1'b0;
        next_warp  = current_warp;

        for (off = 1; off <= NUMBER_OF_WARPS; off = off + 1) begin
            cand = current_warp + off;
            if (cand >= NUMBER_OF_WARPS)
                cand = cand - NUMBER_OF_WARPS;
            if (!next_found && !WARP_STALL[cand] && !WARP_FINISHED[cand]) begin
                next_found = 1'b1;
                next_warp  = cand[WARP_BITS-1:0];
            end
        end
    end
    // Sequential Logic
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            current_warp <= {WARP_BITS{1'b0}};
            state_curr   <= RUN;
            for (i = 0; i < NUMBER_OF_WARPS; i = i + 1) begin
                WARP_STALL[i]    <= 1'b0;
                WARP_FINISHED[i] <= 1'b0;
                WARP_MASK[i]     <= 16'hFFFF;

                case (i)
                    0: WARP_PC[i] <= 16'd0;
                    1: WARP_PC[i] <= 16'd24;
                    2: WARP_PC[i] <= 16'd25;
                    3: WARP_PC[i] <= 16'd26;
                endcase
            end

        end
        else begin
            // Memory completion
        if (mem_done) begin
            if (WARP_STALL[warp_id_from_ms]) begin
                WARP_STALL[warp_id_from_ms] <= 1'b0;
            end

        end
            case (state_curr)
            RUN: begin
                if (WARP_FINISHED[current_warp] || WARP_STALL[current_warp]) begin
                    state_curr <= SWITCH;
                end
                else if (redirect) begin
                    WARP_PC[current_warp] <= pc_target;
                end
                else if (mem_req) begin
                    // FIX #3 (main bug): the PC of the warp issuing the
                    // memory request was never advanced. When the warp
                    // resumed after mem_done, it re-fetched the exact same
                    // load/store instruction and issued the identical
                    // request to memory_scheduler again, forever. Advance
                    // the PC here just like the "normal instruction" path
                    // does, so the warp resumes on the *next* instruction
                    // once its memory op completes.
                    WARP_STALL[current_warp] <= 1'b1;
                    WARP_PC[current_warp]    <= WARP_PC[current_warp] + 16'd1;
                    state_curr               <= SWITCH;
                end
                else if (halt) begin

                    WARP_FINISHED[current_warp] <= 1'b1;
                    state_curr                  <= SWITCH;
                end
                else if (hold) begin
                end
                else begin

                    WARP_PC[current_warp]
                        <= WARP_PC[current_warp] + 16'd1;
                end
            end
            SWITCH: begin
                if (next_found) begin
                    current_warp <= next_warp;
                    state_curr   <= RUN;
                end
                else begin
                    if (done)
                        state_curr <= RUN;
                end
            end
            default:
                state_curr <= RUN;
            endcase
        end
    end
endmodule