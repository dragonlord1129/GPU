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

    reg [15:0] WARP_PC       [0:NUMBER_OF_WARPS-1];
    reg [15:0] WARP_MASK     [0:NUMBER_OF_WARPS-1];
    reg        WARP_STALL    [0:NUMBER_OF_WARPS-1];
    reg        WARP_FINISHED [0:NUMBER_OF_WARPS-1];
    reg [WARP_BITS-1:0] current_warp;

    localparam RUN    = 1'b0;
    localparam SWITCH = 1'b1;
    reg state_curr;

    assign warp_id_to_ms   = current_warp;
    assign current_warp_id = current_warp;
    assign warp_ready      = WARP_PC[current_warp];
    assign warp_ready_mask = WARP_MASK[current_warp];
    assign running = (state_curr == RUN);

    reg done_r;
    integer d;
    always @(*) begin
        done_r = 1'b1;
        for (d = 0; d < NUMBER_OF_WARPS; d = d + 1)
            done_r = done_r & WARP_FINISHED[d];
    end
    assign done = done_r;

    reg                    next_found;
    reg [WARP_BITS-1:0]    next_warp;
    integer off, cand;

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

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            current_warp <= {WARP_BITS{1'b0}};
            state_curr   <= RUN;
            for (i = 0; i < NUMBER_OF_WARPS; i = i + 1) begin
                WARP_STALL[i]    <= 1'b0;
                WARP_FINISHED[i] <= 1'b0;
                WARP_MASK[i]     <= 16'hFFFF;

                // ---------- CORRECTED START ADDRESSES ----------
                // Warp 0: addresses 0..4
                // Warp 1: addresses 5..9
                // Warps 2,3: address 10 (HALT)
                case (i)
                    0: WARP_PC[i] <= 16'd0;
                    1: WARP_PC[i] <= 16'd64;   // warp 1 starts at addr 64
                    2: WARP_PC[i] <= 16'd128;  // warp 2 starts at addr 128
                    3: WARP_PC[i] <= 16'd192;  // warp 3 starts at addr 192 
                endcase
            end
        end else begin
            if (mem_done) begin
                if (WARP_STALL[warp_id_from_ms])
                    WARP_STALL[warp_id_from_ms] <= 1'b0;
            end
            case (state_curr)
                RUN: begin
                    if (WARP_FINISHED[current_warp] || WARP_STALL[current_warp]) begin
                        state_curr <= SWITCH;
                    end else if (redirect) begin
                        WARP_PC[current_warp] <= pc_target;
                    end else if (mem_req) begin
                        WARP_STALL[current_warp] <= 1'b1;
                        WARP_PC[current_warp]    <= WARP_PC[current_warp] + 16'd1;
                        state_curr               <= SWITCH;
                    end else if (halt) begin
                        WARP_FINISHED[current_warp] <= 1'b1;
                        state_curr                  <= SWITCH;
                    end else if (hold) begin
                        // stall
                    end else begin
                        WARP_PC[current_warp] <= WARP_PC[current_warp] + 16'd1;
                    end
                end
                SWITCH: begin
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