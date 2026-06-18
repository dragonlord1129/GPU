// ============================================================================
//  memory_scheduler  (with memory coalescing) -- BUGFIX VERSION
// ============================================================================
module memory_scheduler #(
    parameter LINE_WORDS  = 16,
    parameter OFFSET_BITS = 4
) (
    input             clk,
    input             reset,
    input  [3:0]      request,
    input  [15:0]     active_mask,
    input  [15:0]     addr_in [0:15],
    input  [15:0]     sw_out  [0:15],
    output reg [15:0] lw_out  [0:15],
    output            stall,
    output reg        mem_write,

    input             mem_req,
    input  [1:0]      warp_id_from_ws,
    output reg        mem_done,
    output reg [1:0]  warp_id_to_ws,
    input  [3:0]      lw_destination,
    output reg [3:0]  lw_destination_out,

    input  [15:0]     lw_line_in  [0:LINE_WORDS-1],
    output reg [15:0] addr_out,
    output reg [15:0] sw_line_out [0:LINE_WORDS-1],
    output reg [LINE_WORDS-1:0] sw_word_mask,

    output reg [1:0]  lw_warp_id,
    output reg        lw_ready
);

reg [15:0] ADDR        [0:3][0:15];
reg [15:0] SW_DATA     [0:3][0:15];
reg [1:0]  WARP_NUMBER [0:3];
reg        REQ_DONE    [0:3];
reg        OCCUPIED    [0:3];
reg        REQ_TYPE    [0:3];
reg [3:0]  DESTINATION [0:3];

parameter IDLE      = 3'b000;
parameter WARP      = 3'b001;
parameter REQ_CHECK = 3'b010;
parameter REQ       = 3'b011;
parameter WAIT      = 3'b100;
parameter CAPTURE   = 3'b101;
parameter DONE      = 3'b110;

reg [2:0] state_curr;

integer i, j;

reg request_reg;
reg [1:0] current_warp_in_ms;
reg [1:0] queue_pointer;

reg [15:0] lane_serviced;
reg [15:0] block_members;

assign stall =
    (state_curr == REQ)     ||
    (state_curr == WAIT)    ||
    (state_curr == CAPTURE) ;

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
        current_warp_in_ms <= 2'b00;
        queue_pointer      <= 2'b00;
        lw_destination_out <= 4'h0;
        lane_serviced      <= 16'h0000;
        block_members      <= 16'h0000;
        sw_word_mask       <= {LINE_WORDS{1'b0}};

        for (i = 0; i < 16; i = i + 1)
            lw_out[i] <= 16'h0000;

        for (i = 0; i < LINE_WORDS; i = i + 1)
            sw_line_out[i] <= 16'h0000;

        for (i = 0; i < 4; i = i + 1) begin
            WARP_NUMBER[i] <= 2'b00;
            REQ_DONE[i]    <= 1'b1;
            OCCUPIED[i]    <= 1'b0;
            REQ_TYPE[i]    <= 1'b0;
            DESTINATION[i] <= 4'h0;
            for (j = 0; j < 16; j = j + 1) begin
                ADDR[i][j]    <= 16'h0000;
                SW_DATA[i][j] <= 16'h0000;
            end
        end

    end else begin

        case (state_curr)

            IDLE: begin

                if (mem_req) begin
                    reg found;
                    found = 0;

                    for (i = 0; i < 4; i = i + 1) begin
                        if ((OCCUPIED[i] == 0) && (found == 0)) begin
                            WARP_NUMBER[i] <= warp_id_from_ws;
                            OCCUPIED[i]    <= 1'b1;
                            REQ_DONE[i]    <= 1'b0;
                            REQ_TYPE[i]    <= (request == 4'b0110);
                            if (request == 4'b0110)
                                DESTINATION[i] <= lw_destination;
                            found = 1;
                            // FIX #1: store payload by queue slot i, not by warp ID
                            for (j = 0; j < 16; j = j + 1) begin
                                ADDR[i][j]    <= addr_in[j];
                                SW_DATA[i][j] <= sw_out[j];
                            end
                        end
                    end

                    lane_serviced <= 16'h0000;
                    state_curr    <= WARP;
                end

                else if (!(REQ_DONE[0] && REQ_DONE[1] &&
                           REQ_DONE[2] && REQ_DONE[3])) begin
                    lane_serviced <= 16'h0000;
                    state_curr    <= WARP;
                end

                addr_out     <= 16'h0000;
                sw_word_mask <= {LINE_WORDS{1'b0}};
                mem_write    <= 1'b0;
                mem_done     <= 1'b0;
                lw_ready     <= 1'b0;
            end

            WARP: begin

                if (mem_req) begin
                    reg found;
                    found = 0;

                    for (i = 0; i < 4; i = i + 1) begin
                        if ((OCCUPIED[i] == 0) && (found == 0)) begin
                            WARP_NUMBER[i] <= warp_id_from_ws;
                            OCCUPIED[i]    <= 1'b1;
                            REQ_DONE[i]    <= 1'b0;
                            REQ_TYPE[i]    <= (request == 4'b0110);
                            if (request == 4'b0110)
                                DESTINATION[i] <= lw_destination;
                            found = 1;
                            // FIX #1: store payload by queue slot i
                            for (j = 0; j < 16; j = j + 1) begin
                                ADDR[i][j]    <= addr_in[j];
                                SW_DATA[i][j] <= sw_out[j];
                            end
                        end
                    end
                end

                begin
                    reg found_warp;
                    found_warp = 0;

                    for (i = 0; i < 4; i = i + 1) begin
                        if ((REQ_DONE[i] == 0) && (found_warp == 0)) begin
                            current_warp_in_ms <= WARP_NUMBER[i];
                            queue_pointer      <= i[1:0];
                            found_warp         = 1;
                            request_reg        <= REQ_TYPE[i];
                        end
                    end

                    state_curr  <= REQ_CHECK;
                    // FIX #2: removed stale 'request_reg <= REQ_TYPE[queue_pointer];'
                end
            end

            REQ_CHECK: begin

                if (mem_req) begin
                    reg found;
                    found = 0;

                    for (i = 0; i < 4; i = i + 1) begin
                        if ((OCCUPIED[i] == 0) && (found == 0)) begin
                            WARP_NUMBER[i] <= warp_id_from_ws;
                            OCCUPIED[i]    <= 1'b1;
                            REQ_DONE[i]    <= 1'b0;
                            REQ_TYPE[i]    <= (request == 4'b0110);
                            if (request == 4'b0110)
                                DESTINATION[i] <= lw_destination;
                            found = 1;
                            // FIX #1: store payload by queue slot i
                            for (j = 0; j < 16; j = j + 1) begin
                                ADDR[i][j]    <= addr_in[j];
                                SW_DATA[i][j] <= sw_out[j];
                            end
                        end
                    end
                end

                // FIX #2: removed duplicate assignment, kept only the one using i
                lane_serviced <= 16'h0000;
                state_curr    <= REQ;
            end

            REQ: begin

                // ---- still accept a newly arriving warp (unchanged) ----
                if (mem_req) begin
                    reg found;
                    found = 0;

                    for (i = 0; i < 4; i = i + 1) begin
                        if ((OCCUPIED[i] == 0) && (found == 0)) begin
                            WARP_NUMBER[i] <= warp_id_from_ws;
                            OCCUPIED[i]    <= 1'b1;
                            REQ_DONE[i]    <= 1'b0;
                            REQ_TYPE[i]    <= (request == 4'b0110);
                            if (request == 4'b0110)
                                DESTINATION[i] <= lw_destination;
                            found = 1;
                            // FIX #1: store payload by queue slot i
                            for (j = 0; j < 16; j = j + 1) begin
                                ADDR[i][j]    <= addr_in[j];
                                SW_DATA[i][j] <= sw_out[j];
                            end
                        end
                    end
                end

                // ---- coalesced block dispatch ----
                begin : coalesce
                    reg                    found_leader;
                    integer                leader;
                    integer                l;
                    reg [15-OFFSET_BITS:0]  target_seg;
                    reg [15:0]              members;
                    reg [LINE_WORDS-1:0]    wmask;

                    mem_write <= 1'b0;

                    // 1) lowest-index active lane not yet serviced = block leader
                    found_leader = 1'b0;
                    leader       = 0;
                    for (l = 0; l < 16; l = l + 1) begin
                        if (active_mask[l] && !lane_serviced[l] && !found_leader) begin
                            found_leader = 1'b1;
                            leader       = l;
                        end
                    end

                    if (!found_leader) begin
                        // every active lane has been served -> warp finished
                        state_curr              <= DONE;
                        REQ_DONE[queue_pointer] <= 1'b1;
                        if (request_reg) begin
                            lw_destination_out <= DESTINATION[queue_pointer];
                            lw_ready           <= 1'b1;
                            lw_warp_id         <= current_warp_in_ms;
                        end
                    end
                    else begin
                        // 2) gather every active lane sharing the leader's block
                        // FIX #1: access payload by queue_pointer, not current_warp_in_ms
                        target_seg = ADDR[queue_pointer][leader][15:OFFSET_BITS];
                        members    = 16'h0000;
                        wmask      = {LINE_WORDS{1'b0}};

                        for (l = 0; l < 16; l = l + 1) begin
                            if (active_mask[l] && !lane_serviced[l] &&
                                (ADDR[queue_pointer][l][15:OFFSET_BITS] == target_seg))
                                members[l] = 1'b1;
                        end

                        // 3) issue ONE transaction for the whole block
                        addr_out      <= {target_seg, {OFFSET_BITS{1'b0}}};
                        block_members <= members;
                        lane_serviced <= lane_serviced | members;

                        if (!request_reg) begin
                            // store: pack member words into the line, build mask
                            mem_write <= 1'b1;
                            for (l = 0; l < 16; l = l + 1) begin
                                if (members[l]) begin
                                    // FIX #1: use queue_pointer for data
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
                state_curr <= CAPTURE;
            end

            CAPTURE: begin
                // load: demux each member lane's word out of the returned line
                if (request_reg) begin
                    integer l;
                    for (l = 0; l < 16; l = l + 1) begin
                        if (block_members[l])
                            // FIX #1: use queue_pointer for address look-up
                            lw_out[l] <= lw_line_in[ ADDR[queue_pointer][l][OFFSET_BITS-1:0] ];
                    end
                end

                mem_write  <= 1'b0;
                state_curr <= REQ;
            end

            DONE: begin
                mem_done                <= 1'b1;
                state_curr              <= IDLE;
                OCCUPIED[queue_pointer] <= 1'b0;
                warp_id_to_ws           <= current_warp_in_ms;
            end

            default: begin
                state_curr <= IDLE;
            end

        endcase
    end
end

endmodule