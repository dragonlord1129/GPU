module warp_scheduler #(
    parameter NUMBER_OF_WARPS = 4
) (
    input             clk,
    input             rst,
    input             mem_req,
    input             mem_done,
    input      [1:0]  warp_id_from_ms,
    input             halt,
    input             hold,
    input             redirect,
    input      [15:0] pc_target,

    output     [1:0]  warp_id_to_ms,
    output     [15:0] warp_ready,
    output     [15:0] warp_ready_mask,
    output     [1:0]  current_warp_id,
    output            running,
    output            done
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
            // Memory completion: clear stall and advance PC
            if (mem_done) begin
                if (WARP_STALL[warp_id_from_ms]) begin
                    WARP_STALL[warp_id_from_ms] <= 1'b0;
                    if (!WARP_FINISHED[warp_id_from_ms]) begin
                        WARP_PC[warp_id_from_ms] <= WARP_PC[warp_id_from_ms] + 16'd1;
                    end
                end
            end

            // Scheduling FSM
            case (state_curr)
                RUN: begin
                    // Highest priority: redirect (branch/jump)
                    if (redirect) begin
                        if (!WARP_FINISHED[current_warp]) begin
                            WARP_PC[current_warp] <= pc_target;
                        end
                    end
                    // Memory request: stall and switch
                    else if (mem_req) begin
                        if (!WARP_FINISHED[current_warp] && !WARP_STALL[current_warp]) begin
                            WARP_STALL[current_warp] <= 1'b1;
                            state_curr               <= SWITCH;
                        end
                    end
                    // Halt: finish and switch
                    else if (halt) begin
                        if (!WARP_FINISHED[current_warp]) begin
                            WARP_FINISHED[current_warp] <= 1'b1;
                            state_curr                  <= SWITCH;
                        end
                    end
                    // Hold: freeze PC
                    else if (hold) begin
                        // do nothing
                    end
                    // Normal operation: increment PC
                    else begin
                        if (!WARP_STALL[current_warp] && !WARP_FINISHED[current_warp]) begin
                            // Avoid double increment if mem_done also updates this warp
                            if (!(mem_done && (warp_id_from_ms == current_warp))) begin
                                WARP_PC[current_warp] <= WARP_PC[current_warp] + 16'd1;
                            end
                        end
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