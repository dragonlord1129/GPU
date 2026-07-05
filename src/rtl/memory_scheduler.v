module memory_scheduler #(
    parameter LINE_WORDS  = 16,
    parameter OFFSET_BITS = 4
) (
    input             clk,
    input             reset,
    input  [3:0]      request,
    input  [15:0]     active_mask,
    input  [15:0]     addr_in [0:15],
    input  [31:0]     sw_out  [0:15],
    output reg [31:0] lw_out  [0:15],
    output            stall,
    output reg        mem_write,

    input             mem_req,
    input  [1:0]      warp_id_from_ws,
    output reg        mem_done,
    output reg [1:0]  warp_id_to_ws,
    input  [3:0]      lw_destination,
    output reg [3:0]  lw_destination_out,

    input  [31:0]     lw_line_in  [0:LINE_WORDS-1],
    output reg [15:0] addr_out,
    output reg [31:0] sw_line_out [0:LINE_WORDS-1],
    output reg [LINE_WORDS-1:0] sw_word_mask,

    output reg [1:0]  lw_warp_id,
    output reg        lw_ready
);

    // ---- Request latch ----
    reg        req_pending;
    reg [3:0]  req_type;
    reg [1:0]  req_warp;
    reg [15:0] req_mask;
    reg [15:0] req_addr [0:15];
    reg [15:0] req_sw   [0:15];
    reg [3:0]  req_dst;

    // ---- Queue slots ----
    reg [15:0] ADDR        [0:3][0:15];
    reg [15:0] SW_DATA     [0:3][0:15];
    reg [15:0] ACTIVE_MASK [0:3];
    reg [1:0]  WARP_NUMBER [0:3];
    reg        REQ_DONE    [0:3];
    reg        OCCUPIED    [0:3];
    reg        REQ_TYPE    [0:3];       // 1 = load, 0 = store
    reg [3:0]  DESTINATION [0:3];

    wire queue_full  = OCCUPIED[0] & OCCUPIED[1] & OCCUPIED[2] & OCCUPIED[3];
    wire occupied_any = OCCUPIED[0] | OCCUPIED[1] | OCCUPIED[2] | OCCUPIED[3];

    parameter IDLE      = 3'b000,
              WARP      = 3'b001,
              REQ_CHECK = 3'b010,
              REQ       = 3'b011,
              WAIT      = 3'b100,
              CAPTURE   = 3'b101,
              DONE      = 3'b110;

    reg [2:0] state_curr;
    integer i, j;
    reg [1:0] queue_pointer;
    reg       request_reg;               // 1 = load, 0 = store
    reg [15:0] lane_serviced;
    reg [15:0] block_members;

    assign stall = queue_full || req_pending;

    // ---- Request latch ----
    always @(posedge clk) begin
        if (reset) begin
            req_pending <= 1'b0;
        end else begin
            if (mem_req && !req_pending) begin
                req_pending <= 1'b1;
                req_type    <= request;
                req_warp    <= warp_id_from_ws;
                req_mask    <= active_mask;
                req_dst     <= lw_destination;
                for (i = 0; i < 16; i = i + 1) begin
                    req_addr[i] <= addr_in[i];
                    req_sw[i]   <= sw_out[i];
                end
            end
        end
    end

    // ---- Main FSM ----
    always @(posedge clk) begin
        if (reset) begin
            state_curr         <= IDLE;
            addr_out           <= 16'h0000;
            mem_write          <= 1'b0;
            request_reg        <= 1'b0;
            lw_warp_id         <= 2'b00;
            lw_ready           <= 1'b0;
            mem_done           <= 1'b0;
            warp_id_to_ws      <= 2'b00;
            queue_pointer      <= 2'b00;
            lw_destination_out <= 4'h0;
            lane_serviced      <= 16'h0000;
            block_members      <= 16'h0000;
            sw_word_mask       <= {LINE_WORDS{1'b0}};

            for (i = 0; i < 16; i = i + 1) lw_out[i] <= 16'h0000;
            for (i = 0; i < LINE_WORDS; i = i + 1) sw_line_out[i] <= 16'h0000;

            for (i = 0; i < 4; i = i + 1) begin
                WARP_NUMBER[i] <= 2'b00;
                REQ_DONE[i]    <= 1'b1;
                OCCUPIED[i]    <= 1'b0;
                REQ_TYPE[i]    <= 1'b0;
                DESTINATION[i] <= 4'h0;
                ACTIVE_MASK[i] <= 16'h0000;
                for (j = 0; j < 16; j = j + 1) begin
                    ADDR[i][j]    <= 16'h0000;
                    SW_DATA[i][j] <= 16'h0000;
                end
            end

        end else begin

            // ---- Enqueue pending request ----
            if (req_pending && !queue_full) begin
                integer slot;
                reg found;
                found = 0;
                for (slot = 0; slot < 4; slot = slot + 1) begin
                    if (!OCCUPIED[slot] && !found) begin
                        OCCUPIED[slot]    <= 1'b1;
                        REQ_DONE[slot]    <= 1'b0;
                        WARP_NUMBER[slot] <= req_warp;
                        REQ_TYPE[slot]    <= (req_type == 4'b0110);
                        if (req_type == 4'b0110)
                            DESTINATION[slot] <= req_dst;
                        ACTIVE_MASK[slot] <= req_mask;
                        for (i = 0; i < 16; i = i + 1) begin
                            ADDR[slot][i]    <= req_addr[i];
                            SW_DATA[slot][i] <= req_sw[i];
                        end
                        found = 1;
                    end
                end
                req_pending <= 1'b0;
            end

            // ---- State machine ----
            case (state_curr)

                IDLE: begin
                    if (occupied_any) begin
                        lane_serviced <= 16'h0000;
                        state_curr    <= WARP;
                    end
                    addr_out     <= 16'h0000;
                    sw_word_mask <= {LINE_WORDS{1'b0}};
                    mem_write    <= 1'b0;
                    mem_done     <= 1'b0;
                    // NOTE: lw_ready is intentionally NOT cleared here.
                    // See REQ_CHECK below for why.
                end

                WARP: begin
                    // select next unserviced warp
                    integer k;
                    reg found_warp;
                    found_warp = 0;
                    for (k = 0; k < 4; k = k + 1) begin
                        if (!REQ_DONE[k] && !found_warp) begin
                            queue_pointer  <= k[1:0];
                            request_reg    <= REQ_TYPE[k];
                            found_warp     = 1;
                        end
                    end
                    if (found_warp)
                        state_curr <= REQ_CHECK;
                    else
                        state_curr <= IDLE;   // no pending requests
                end

                REQ_CHECK: begin
                    lane_serviced <= 16'h0000;
                    lw_ready      <= 1'b0;   // invalidate any previous load result
                    state_curr    <= REQ;
                end

                REQ: begin
                    // coalesced block dispatch
                    begin : coalesce
                        reg                    found_leader;
                        integer                leader, l;
                        reg [15-OFFSET_BITS:0] target_seg;
                        reg [15:0]             members;
                        reg [LINE_WORDS-1:0]   wmask;

                        mem_write <= 1'b0;
                        found_leader = 1'b0;
                        leader       = 0;

                        for (l = 0; l < 16; l = l + 1) begin
                            if (ACTIVE_MASK[queue_pointer][l] && !lane_serviced[l] && !found_leader) begin
                                found_leader = 1'b1;
                                leader       = l;
                            end
                        end

                        if (!found_leader) begin
                            state_curr              <= DONE;
                            REQ_DONE[queue_pointer] <= 1'b1;
                            if (request_reg) begin
                                lw_destination_out <= DESTINATION[queue_pointer];
                                lw_ready           <= 1'b1;
                                lw_warp_id         <= WARP_NUMBER[queue_pointer];
                            end
                        end else begin
                            target_seg = ADDR[queue_pointer][leader][15:OFFSET_BITS];
                            members    = 16'h0000;
                            wmask      = {LINE_WORDS{1'b0}};

                            for (l = 0; l < 16; l = l + 1) begin
                                if (ACTIVE_MASK[queue_pointer][l] && !lane_serviced[l] &&
                                    (ADDR[queue_pointer][l][15:OFFSET_BITS] == target_seg))
                                    members[l] = 1'b1;
                            end

                            addr_out      <= {target_seg, {OFFSET_BITS{1'b0}}};
                            block_members <= members;
                            lane_serviced <= lane_serviced | members;

                            if (!request_reg) begin          // store
                                mem_write <= 1'b1;
                                for (l = 0; l < 16; l = l + 1) begin
                                    if (members[l]) begin
                                        sw_line_out[ ADDR[queue_pointer][l][OFFSET_BITS-1:0] ]
                                            <= SW_DATA[queue_pointer][l];
                                        wmask[ ADDR[queue_pointer][l][OFFSET_BITS-1:0] ] = 1'b1;
                                    end
                                end
                                sw_word_mask <= wmask;
                            end

                            state_curr <= WAIT;
                        end
                    end
                end

                WAIT: begin
                    mem_write <= 1'b0;          // clear write enable (single‑cycle pulse)
                    state_curr <= CAPTURE;
                end

                CAPTURE: begin
                    if (request_reg) begin
                        integer l;
                        for (l = 0; l < 16; l = l + 1) begin
                            if (block_members[l])
                                lw_out[l] <= lw_line_in[ ADDR[queue_pointer][l][OFFSET_BITS-1:0] ];
                        end
                    end
                    // mem_write already cleared; no need to clear again
                    state_curr <= REQ;
                end

                DONE: begin
                    mem_done                <= 1'b1;
                    state_curr              <= IDLE;
                    OCCUPIED[queue_pointer] <= 1'b0;
                    warp_id_to_ws           <= WARP_NUMBER[queue_pointer];
                end

                default: state_curr <= IDLE;
            endcase
        end
    end
endmodule