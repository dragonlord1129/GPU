// ============================================================================
// gpu_top – pipelined memory request (fixes combinational race)
// ============================================================================
module gpu_top #(
    parameter NUMBER_OF_WARPS   = 4,
    parameter NUMBER_OF_THREADS = 16,
    parameter DATA_WIDTH        = 16
)(
    input             clk,
    input             reset,
    input      [3:0]  lane_select,
    output     [15:0] debug_pc,
    output     [15:0] debug_regs [0:3][0:15][0:15],
    output     [15:0] debug_lw_out,
    output     [15:0] debug_alu_result,
    output            done
);

    // ---------------- warp scheduler <-> top ----------------
    wire        mem_done;
    wire [1:0]  warp_id_from_ms;
    wire [1:0]  warp_id_to_ms;
    wire [1:0]  current_warp_id;
    wire [15:0] warp_ready;
    wire [15:0] warp_ready_mask;
    wire        running;

    // ---------------- decode ----------------
    wire [31:0] instr;
    wire [3:0]  opcode = instr[15:12];
    wire [3:0]  A1 = instr[3:0];
    wire [3:0]  A2 = instr[7:4];
    wire [3:0]  A3 = instr[11:8];
    wire [15:0] imm = instr[31:16];
    wire [15:0] imm_out;

    // ---------------- control unit ----------------
    reg  [3:0] alu_control;
    reg        alu_source;
    reg        reg_we_ctrl;
    reg        is_lw, is_sw, is_branch_beq, is_branch_blt, is_jump, is_halt;

    always @(*) begin
        alu_control   = 4'b0000;
        alu_source    = 1'b0;
        reg_we_ctrl   = 1'b0;
        is_lw         = 1'b0;
        is_sw         = 1'b0;
        is_branch_beq = 1'b0;
        is_branch_blt = 1'b0;
        is_jump       = 1'b0;
        is_halt       = 1'b0;
        case (opcode)
            4'b0000: begin alu_control=4'b0000; reg_we_ctrl=1; end
            4'b0001: begin alu_control=4'b0001; reg_we_ctrl=1; end
            4'b0010: begin alu_control=4'b0010; reg_we_ctrl=1; end
            4'b0011: begin alu_control=4'b0011; reg_we_ctrl=1; end
            4'b0100: begin alu_control=4'b0100; reg_we_ctrl=1; end
            4'b0101: begin alu_control=4'b0101; reg_we_ctrl=1; end
            4'b0110: begin alu_control=4'b0000; alu_source=1; is_lw=1; end
            4'b0111: begin alu_control=4'b0000; alu_source=1; is_sw=1; end
            4'b1000: begin alu_control=4'b0000; alu_source=1; reg_we_ctrl=1; end
            4'b1001: begin alu_control=4'b0001; alu_source=1; reg_we_ctrl=1; end
            4'b1010: begin alu_control=4'b1001; reg_we_ctrl=1; end
            4'b1011: begin alu_control=4'b0001; is_branch_beq=1; end
            4'b1100: begin alu_control=4'b1001; is_branch_blt=1; end
            4'b1101: begin alu_source=1;        is_jump=1; end
            4'b1110: begin alu_control=4'b0111; reg_we_ctrl=1; end
            4'b1111: begin is_halt=1; end
            default: ;
        endcase
    end

    wire is_mem = is_lw | is_sw;
    wire ms_stall;
    wire mem_req_delayed;
    wire warp_mem_req;

    // ----- Pipelining registers for memory requests -----
    reg         mem_pending;
    reg [1:0]   mem_pending_warp;
    reg [15:0]  mem_pending_addr  [0:NUMBER_OF_THREADS-1];
    reg [15:0]  mem_pending_sw    [0:NUMBER_OF_THREADS-1];
    reg [3:0]   mem_pending_lwdst;
    reg         mem_pending_is_load;

    assign mem_req_delayed = mem_pending && !ms_stall;
    assign warp_mem_req = running && is_mem && !mem_pending && !ms_stall;

    wire hold = running && is_mem && ms_stall;
    wire halt = running && is_halt;

    // ---------------- register files (forwarding version) ----------------
    wire [DATA_WIDTH-1:0] RS1_warps [0:NUMBER_OF_WARPS-1][0:NUMBER_OF_THREADS-1];
    wire [DATA_WIDTH-1:0] RS2_warps [0:NUMBER_OF_WARPS-1][0:NUMBER_OF_THREADS-1];

    wire [DATA_WIDTH-1:0] RS1 [0:NUMBER_OF_THREADS-1];
    wire [DATA_WIDTH-1:0] RS2 [0:NUMBER_OF_THREADS-1];

    wire [DATA_WIDTH-1:0] alu_result [0:NUMBER_OF_THREADS-1];
    wire                  alu_zero   [0:NUMBER_OF_THREADS-1];

    wire [DATA_WIDTH-1:0] lw_out [0:NUMBER_OF_THREADS-1];
    wire [3:0]            lw_destination_out;
    wire                  lw_ready;
    wire [1:0]            lw_warp_id;

    genvar w, i, r;
    generate
        for (w = 0; w < NUMBER_OF_WARPS; w = w + 1) begin : warp_array
            wire        lw_we_warp = lw_ready && (w == lw_warp_id);
            wire [3:0]  A3_eff     = lw_we_warp ? lw_destination_out : A3;

            for (i = 0; i < NUMBER_OF_THREADS; i = i + 1) begin : lane_array
                wire [DATA_WIDTH-1:0] WD = lw_we_warp ? lw_out[i] : alu_result[i];

                wire normal_we = running && reg_we_ctrl && warp_ready_mask[i]
                                 && (w == current_warp_id) && !mem_pending;
                wire we = normal_we || lw_we_warp;

                reg_file #(.DATA_WIDTH(DATA_WIDTH)) reg_inst (
                    .clk(clk), .reset(reset),
                    .A1(A1), .A2(A2), .A3(A3_eff),
                    .RS1(RS1_warps[w][i]), .RS2(RS2_warps[w][i]),
                    .block_idx (w[DATA_WIDTH-1:0]),
                    .block_dim (16'd16),
                    .thread_idx(i[DATA_WIDTH-1:0]),
                    .WD(WD), .we(we), .reg_en(1'b1)
                );

                for (r = 0; r < 16; r = r + 1) begin : debug_copy
                    assign debug_regs[w][i][r] = reg_inst.REGISTER[r];
                end
            end
        end
    endgenerate

    generate
        for (i = 0; i < NUMBER_OF_THREADS; i = i + 1) begin : sel
            assign RS1[i] = RS1_warps[current_warp_id][i];
            assign RS2[i] = RS2_warps[current_warp_id][i];
        end
    endgenerate

    generate
        for (i = 0; i < NUMBER_OF_THREADS; i = i + 1) begin : alu_lane
            wire [DATA_WIDTH-1:0] B = alu_source ? imm_out : RS2[i];
            alu #(.WIDTH(DATA_WIDTH), .ALU_WIDTH(4)) alu_inst (
                .A(RS1[i]), .B(B), .ALUControl(alu_control),
                .result(alu_result[i]),
                .carry(), .zero(alu_zero[i]),
                .overflow(), .negative(), .divide_by_zero()
            );
        end
    endgenerate

    wire branch_taken = (is_branch_beq && alu_zero[0]) ||
                        (is_branch_blt && alu_result[0][0]);
    wire redirect  = running && (branch_taken || is_jump);
    wire [15:0] pc_target = warp_ready + imm_out;

    // ---------------- Capture memory request ----------------
    integer j;
    always @(posedge clk) begin
        if (reset) begin
            mem_pending <= 1'b0;
        end else begin
            if (running && is_mem && !mem_pending && !ms_stall) begin
                mem_pending <= 1'b1;
                mem_pending_warp <= current_warp_id;
                for (j = 0; j < NUMBER_OF_THREADS; j = j + 1) begin
                    mem_pending_addr[j] <= alu_result[j];
                    mem_pending_sw[j]   <= RS2[j];
                end
                mem_pending_lwdst   <= A3;
                mem_pending_is_load <= is_lw;
            end
            if (mem_done && (warp_id_from_ms == mem_pending_warp))
                mem_pending <= 1'b0;
        end
    end

    // ---------------- memory scheduler + line memory ----------------
    wire        mem_write;
    wire [15:0] addr_out;
    wire [15:0] sw_line_out [0:15];
    wire [15:0] sw_word_mask_w;
    wire [15:0] lw_line_in  [0:15];

    memory_scheduler #(.LINE_WORDS(16), .OFFSET_BITS(4)) scheduler_inst (
        .clk(clk), .reset(reset),
        .request(mem_pending_is_load ? 4'b0110 : 4'b0111),
        .active_mask(warp_ready_mask),
        .addr_in(mem_pending_addr),
        .sw_out(mem_pending_sw),
        .lw_out(lw_out),
        .stall(ms_stall),
        .mem_write(mem_write),
        .mem_req(mem_req_delayed),
        .warp_id_from_ws(mem_pending ? mem_pending_warp : current_warp_id),
        .mem_done(mem_done),
        .warp_id_to_ws(warp_id_from_ms),
        .lw_destination(mem_pending_lwdst),
        .lw_destination_out(lw_destination_out),
        .lw_line_in(lw_line_in),
        .addr_out(addr_out),
        .sw_line_out(sw_line_out),
        .sw_word_mask(sw_word_mask_w),
        .lw_warp_id(lw_warp_id),
        .lw_ready(lw_ready)
    );

    data_memory_line #(.LINE_WORDS(16), .OFFSET_BITS(4), .INDEX_BITS(8)) dmem (
        .clk(clk), .mem_write(mem_write),
        .addr_base(addr_out),
        .sw_word_mask(sw_word_mask_w),
        .sw_line_out(sw_line_out),
        .lw_line_in(lw_line_in)
    );

    // ---------------- warp scheduler ----------------
    warp_scheduler #(.NUMBER_OF_WARPS(NUMBER_OF_WARPS)) warp_inst (
        .clk(clk), .rst(reset),
        .mem_req(warp_mem_req),
        .mem_done(mem_done),
        .warp_id_from_ms(warp_id_from_ms),
        .halt(halt),
        .hold(hold),
        .redirect(redirect), .pc_target(pc_target),
        .warp_id_to_ms(warp_id_to_ms),
        .warp_ready(warp_ready),
        .warp_ready_mask(warp_ready_mask),
        .current_warp_id(current_warp_id),
        .running(running),
        .done(done)
    );

    // ---------------- instruction memory ----------------
    instruction_memory imem (
        .A(warp_ready[7:0]), .RD(instr)
    );

    // ---------------- immediate ----------------
    imm_gen #(.DATA_WIDTH(16)) imm_inst (.imm(imm), .imm_out(imm_out));

    // ---------------- debug ----------------
    assign debug_pc         = warp_ready;
    assign debug_lw_out     = lw_out[lane_select];
    assign debug_alu_result = alu_result[lane_select];
endmodule