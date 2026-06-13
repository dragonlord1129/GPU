// ============================================================================
//  gpu_top  -- pure-Verilog SIMT core (4 warps x 16 lanes)
// ----------------------------------------------------------------------------
//  Wires together the ACTUAL supplied modules:
//      warp_scheduler (extended: running/redirect/pc_target)
//      memory_scheduler (coalescing)  + data_memory_line (16x data_memory)
//      instruction_memory, alu (+booth+divider), reg_file, imm_gen
//
//  Execution model: switch-on-stall single-issue. The warp scheduler presents
//  one warp's PC each cycle; the lane datapath executes that instruction in one
//  cycle (ALU is combinational). A LW/SW pulses mem_req for one cycle, which
//  stalls the warp and hands the coalesced request to the memory_scheduler; the
//  scheduler runs its multi-cycle FSM and, on completion, pulses mem_done (which
//  un-stalls the warp and steps its PC) and -- for loads -- lw_ready, which
//  writes the returned word back into the destination register of the (still
//  stalled, non-current) loading warp.
//
//  Register conventions (see reg_file)a:  R0=0, R13=blockIdx(=warp id),
//  R14=blockDim(=16), R15=threadIdx(=lane id).
//  No thread divergence: every warp mask is 0xFFFF.
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
    wire [1:0]  warp_id_from_ms;   // ms.warp_id_to_ws
    wire [1:0]  warp_id_to_ms;     // ws.warp_id_to_ms
    wire [1:0]  current_warp_id;
    wire [15:0] warp_ready;        // current warp PC
    wire [15:0] warp_ready_mask;
    wire        running;

    // ---------------- decode ----------------
    wire [31:0] instr;
    wire [3:0]  opcode = instr[15:12];
    wire [3:0]  A1 = instr[3:0];   // rs1
    wire [3:0]  A2 = instr[7:4];   // rs2
    wire [3:0]  A3 = instr[11:8];  // rd
    wire [15:0] imm = instr[31:16];
    wire [15:0] imm_out;

    // ---------------- control unit ----------------
    reg  [3:0] alu_control;
    reg        alu_source;   // 1 => ALU B = imm
    reg        reg_we_ctrl;  // normal (ALU) register write
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
            4'b0000: begin alu_control=4'b0000; reg_we_ctrl=1; end           // ADD
            4'b0001: begin alu_control=4'b0001; reg_we_ctrl=1; end           // SUB
            4'b0010: begin alu_control=4'b0010; reg_we_ctrl=1; end           // AND
            4'b0011: begin alu_control=4'b0011; reg_we_ctrl=1; end           // OR
            4'b0100: begin alu_control=4'b0100; reg_we_ctrl=1; end           // XOR
            4'b0101: begin alu_control=4'b0101; reg_we_ctrl=1; end           // MUL (low)
            4'b0110: begin alu_control=4'b0000; alu_source=1; is_lw=1; end   // LW  addr=rs1+imm
            4'b0111: begin alu_control=4'b0000; alu_source=1; is_sw=1; end   // SW  addr=rs1+imm
            4'b1000: begin alu_control=4'b0000; alu_source=1; reg_we_ctrl=1; end // ADDI
            4'b1001: begin alu_control=4'b0001; alu_source=1; reg_we_ctrl=1; end // SUBI
            4'b1010: begin alu_control=4'b1001; reg_we_ctrl=1; end           // SLT
            4'b1011: begin alu_control=4'b0001; is_branch_beq=1; end         // BEQ (sub->zero)
            4'b1100: begin alu_control=4'b1001; is_branch_blt=1; end         // BLT (slt)
            4'b1101: begin alu_source=1;        is_jump=1; end               // JMP pc+=imm
            4'b1110: begin alu_control=4'b0111; reg_we_ctrl=1; end           // DIV
            4'b1111: begin is_halt=1; end                                    // HALT
            default: ;
        endcase
    end

    wire is_mem = is_lw | is_sw;
    wire ms_can_accept;
    wire mem_req = !reset && running && is_mem && ms_can_accept;
    wire hold    = running && is_mem && !ms_can_accept;  // scheduler busy: freeze
    wire halt    = running && is_halt;

    // ---------------- register files (4 warps x 16 lanes) ----------------
    wire [DATA_WIDTH-1:0] RS1_warps [0:NUMBER_OF_WARPS-1][0:NUMBER_OF_THREADS-1];
    wire [DATA_WIDTH-1:0] RS2_warps [0:NUMBER_OF_WARPS-1][0:NUMBER_OF_THREADS-1];

    // current-warp operands feeding the ALUs / memory
    wire [DATA_WIDTH-1:0] RS1 [0:NUMBER_OF_THREADS-1];
    wire [DATA_WIDTH-1:0] RS2 [0:NUMBER_OF_THREADS-1];

    // ALU results / flags per lane
    wire [DATA_WIDTH-1:0] alu_result [0:NUMBER_OF_THREADS-1];
    wire                  alu_zero   [0:NUMBER_OF_THREADS-1];

    // memory scheduler load return + handshake
    wire [DATA_WIDTH-1:0] lw_out [0:NUMBER_OF_THREADS-1];
    wire [3:0]            lw_destination_out;
    wire                  lw_ready;
    wire [1:0]            lw_warp_id;

    genvar w, i, r;
    generate
        for (w = 0; w < NUMBER_OF_WARPS; w = w + 1) begin : warp_array
            // per-warp effective write address: loading warp uses lw dest
            wire        lw_we_warp = lw_ready && (w == lw_warp_id);
            wire [3:0]  A3_eff     = lw_we_warp ? lw_destination_out : A3;

            for (i = 0; i < NUMBER_OF_THREADS; i = i + 1) begin : lane_array
                // write-data mux: loading warp gets memory word, else ALU result
                wire [DATA_WIDTH-1:0] WD = lw_we_warp ? lw_out[i] : alu_result[i];

                // write enable: normal ALU writeback (only current warp, RUN,
                // non-mem) OR deferred load writeback (loading warp, all lanes)
                wire normal_we = running && reg_we_ctrl && warp_ready_mask[i]
                                 && (w == current_warp_id) && !mem_req;
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

    // select current warp's operands
    generate
        for (i = 0; i < NUMBER_OF_THREADS; i = i + 1) begin : sel
            assign RS1[i] = RS1_warps[current_warp_id][i];
            assign RS2[i] = RS2_warps[current_warp_id][i];
        end
    endgenerate

    // per-lane ALU
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

    // ---------------- branch / jump next-PC ----------------
    wire branch_taken = (is_branch_beq && alu_zero[0]) ||      // rs1==rs2
                        (is_branch_blt && alu_result[0][0]);   // slt lane0
    wire redirect  = running && (branch_taken || is_jump);
    wire [15:0] pc_target = warp_ready + imm_out;

    // ---------------- memory scheduler + line memory ----------------
    wire        mem_write;
    wire [15:0] addr_out;
    wire [15:0] sw_line_out [0:15];
    wire [15:0] sw_word_mask_w;
    wire [15:0] lw_line_in  [0:15];
    wire        ms_stall;

    memory_scheduler #(.LINE_WORDS(16), .OFFSET_BITS(4)) scheduler_inst (
        .clk(clk), .reset(reset),
        .request(opcode),
        .active_mask(warp_ready_mask),
        .addr_in(alu_result),       // per-lane address = rs1+imm
        .sw_out(RS2),               // per-lane store data = rs2
        .lw_out(lw_out),
        .stall(ms_stall),
        .mem_write(mem_write),
        .mem_req(mem_req),
        .warp_id_from_ws(warp_id_to_ms),
        .mem_done(mem_done),
        .warp_id_to_ws(warp_id_from_ms),
        .lw_destination(A3),
        .lw_destination_out(lw_destination_out),
        .lw_line_in(lw_line_in),
        .addr_out(addr_out),
        .sw_line_out(sw_line_out),
        .sw_word_mask(sw_word_mask_w[15:0]),
        .lw_warp_id(lw_warp_id),
        .lw_ready(lw_ready),
        .can_accept(ms_can_accept)
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
        .mem_req(mem_req), .mem_done(mem_done),
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