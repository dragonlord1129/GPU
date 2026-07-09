module gpu_top (
    input  wire clk,
    input  wire rst,
    output wire done
);

    localparam DATA_WIDTH      = 16;
    localparam NUM_REGS        = 16;
    localparam LANES           = 16;
    localparam LINE_WORDS      = 16;
    localparam OFFSET_BITS     = 4;
    localparam ADDR_WIDTH      = 12;
    localparam NUMBER_OF_WARPS = 4;
    localparam WARP_BITS       = 2;

    genvar i;

    //=====================================================================
    // 1. WARP SCHEDULER
    //=====================================================================
    wire [15:0]          warp_ready_pc;
    wire [15:0]          warp_ready_mask;
    wire [WARP_BITS-1:0] current_warp_id;
    wire [WARP_BITS-1:0] warp_id_to_ms;
    wire                 warp_running;
    wire                 warp_done_all;

    wire [WARP_BITS-1:0] ms_warp_id_to_ws;
    wire                 mem_req_pulse;
    wire                 mem_done;
    wire                 halt_d;
    wire                 ms_stall;
    wire                 hold;
    wire                 redirect;
    wire [15:0]          pc_target;

    warp_scheduler #(.NUMBER_OF_WARPS(4), .WARP_BITS(2)) u_warp_scheduler (
        .clk(clk), .rst(rst),
        .mem_req(mem_req_pulse), .mem_done(mem_done), .warp_id_from_ms(ms_warp_id_to_ws),
        .halt(halt_d), .hold(hold), .redirect(redirect), .pc_target(pc_target),
        .warp_id_to_ms(warp_id_to_ms), .warp_ready(warp_ready_pc),
        .warp_ready_mask(warp_ready_mask), .current_warp_id(current_warp_id),
        .running(warp_running), .done(warp_done_all)
    );
    assign done = warp_done_all;

    //=====================================================================
    // 2. INSTRUCTION FETCH & DECODE
    //=====================================================================
    wire [31:0] instr;
    instruction_memory u_imem (.A(warp_ready_pc), .RD(instr));

    wire [3:0]  opcode, rd_field, rs1_field, rs2_field;
    wire [15:0] imm_field;
    instruction_decoder u_idecode (
        .instruction(instr), .opcode(opcode), .rd(rd_field), .rs1(rs1_field),
        .rs2(rs2_field), .imm(imm_field)
    );

    wire        RegWrite, MemRead, MemWrite, ALUSrc, Branch, Jump, Halt;
    wire [3:0]  ALUControl;
    wire [1:0]  ResultSrc;
    main_decoder u_main_decoder (
        .opcode(opcode), .RegWrite(RegWrite), .MemRead(MemRead), .MemWrite(MemWrite),
        .ALUSrc(ALUSrc), .Branch(Branch), .Jump(Jump), .Halt(Halt),
        .ALUControl(ALUControl), .ResultSrc(ResultSrc)
    );
    assign halt_d = Halt;

    //=====================================================================
    // 3. IMMEDIATE & REGISTER FILE
    //=====================================================================
    wire [15:0] imm_out;
    imm_gen #(.DATA_WIDTH(16)) u_imm_gen (.imm(imm_field), .imm_out(imm_out));

    wire [15:0] rs1_data [0:15], rs2_data [0:15];
    wire [3:0]  wb_rd_addr;
    wire [15:0] wb_active_mask;
    wire        wb_reg_write;
    wire [15:0] wbmux_out [0:15];

    reg_file_simt #(.DATA_WIDTH(16), .NUM_REGS(16), .LANES(16)) u_regfile (
        .clk(clk), .reset(rst),
        .rs1_addr(rs1_field), .rs2_addr(rs2_field), .rd_addr(wb_rd_addr),
        .active_mask(wb_active_mask), .write_data(wbmux_out), .reg_write(wb_reg_write),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    //=====================================================================
    // 4. ALU
    //=====================================================================
    wire [15:0] alu_b [0:15];
    generate for (i=0;i<16;i=i+1) begin : gen_alu_b
        assign alu_b[i] = ALUSrc ? imm_out : rs2_data[i];
    end endgenerate

    wire [15:0] alu_result [0:15];
    simt_alu #(.LANES(16), .WIDTH(16)) u_simt_alu (
        .A(rs1_data), .B(alu_b), .ALUControl(ALUControl), .Result(alu_result)
    );

    //=====================================================================
    // 5. MEMORY SUBSYSTEM
    //=====================================================================
    wire [31:0] lw_line_in [0:15];
    wire [15:0] ms_addr_out;
    wire        ms_mem_write;
    wire [31:0] ms_sw_line_out [0:15];
    wire [LINE_WORDS-1:0] ms_sw_word_mask;

    data_memory_line #(.DATA_WIDTH(32), .LINE_WORDS(16), .OFFSET_BITS(4), .ADDR_WIDTH(12)) u_dmem_line (
        .clk(clk), .mem_write(ms_mem_write), .addr_base(ms_addr_out[11:4]),
        .sw_word_mask(ms_sw_word_mask), .sw_line_out(ms_sw_line_out), .lw_line_in(lw_line_in)
    );

    wire [31:0] sw_out_ext [0:15];
    generate for (i=0;i<16;i=i+1) begin : gen_sw_ext
        assign sw_out_ext[i] = {16'b0, rs2_data[i]};
    end endgenerate

    wire [31:0] lw_out [0:15];
    wire [3:0]  lw_destination_out;  // still from scheduler, but we'll ignore it
    wire [WARP_BITS-1:0] lw_warp_id;
    wire        lw_ready;

    memory_scheduler #(.LINE_WORDS(16), .OFFSET_BITS(4)) u_mem_sched (
        .clk(clk), .reset(rst),
        .lw_line_in(lw_line_in),
        .addr_out(ms_addr_out), .mem_write(ms_mem_write),
        .sw_line_out(ms_sw_line_out), .sw_word_mask(ms_sw_word_mask),
        .request(opcode), .active_mask(warp_ready_mask),
        .addr_in(alu_result), .sw_out(sw_out_ext),
        .mem_req(mem_req_pulse), .warp_id_from_ws(warp_id_to_ms),
        .lw_destination(rd_field),
        .lw_out(lw_out), .stall(ms_stall), .mem_done(mem_done),
        .warp_id_to_ws(ms_warp_id_to_ws), .lw_destination_out(lw_destination_out),
        .lw_warp_id(lw_warp_id), .lw_ready(lw_ready)
    );

    // Truncate lw_out to 16 bits
    wire [15:0] lw_out_trunc [0:15];
    generate for (i=0;i<16;i=i+1) begin : gen_lw_trunc
        assign lw_out_trunc[i] = lw_out[i][15:0];
    end endgenerate

    //=====================================================================
    // 6. PER‑WARP PENDING, LOAD FLAG, DESTINATION, MASK
    //=====================================================================
    reg [NUMBER_OF_WARPS-1:0] mem_pending;
    reg [NUMBER_OF_WARPS-1:0] mem_is_load;
    reg [3:0] mem_dest [0:NUMBER_OF_WARPS-1];
    wire is_mem_instr = MemRead | MemWrite;
    assign mem_req_pulse = is_mem_instr & ~mem_pending[current_warp_id] & ~ms_stall;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_pending <= 0;
            for (integer j = 0; j < NUMBER_OF_WARPS; j = j + 1)
                mem_is_load[j] <= 1'b0;
        end else begin
            if (mem_req_pulse) begin
                mem_pending[warp_id_to_ms] <= 1'b1;
                mem_is_load[warp_id_to_ms] <= MemRead;
                mem_dest[warp_id_to_ms]    <= rd_field;
            end
            if (mem_done) begin
                mem_pending[ms_warp_id_to_ws] <= 1'b0;
            end
        end
    end
    assign hold = mem_pending[current_warp_id] | ms_stall;

    reg [15:0] warp_mask_reg [0:NUMBER_OF_WARPS-1];
    always @(posedge clk) if (mem_req_pulse) warp_mask_reg[warp_id_to_ms] <= warp_ready_mask;

    //=====================================================================
    // 7. LOAD COMPLETION CAPTURE (uses mem_is_load, mem_dest)
    //=====================================================================
    reg [15:0] captured_lw_data [0:15];
    reg [3:0]  captured_lw_dest;
    reg [1:0]  captured_lw_warp_id;
    reg        load_write_pulse;

    always @(posedge clk) begin
        if (rst) begin
            load_write_pulse <= 1'b0;
        end else begin
            if (mem_done && mem_is_load[ms_warp_id_to_ws]) begin
                for (integer j = 0; j < 16; j = j + 1)
                    captured_lw_data[j] <= lw_out_trunc[j];
                captured_lw_dest    <= mem_dest[ms_warp_id_to_ws];
                captured_lw_warp_id <= ms_warp_id_to_ws;
                load_write_pulse    <= 1'b1;
            end else begin
                load_write_pulse    <= 1'b0;
            end
        end
    end

    //=====================================================================
    // 8. WRITE‑BACK MUX
    //=====================================================================
    generate for (i=0;i<16;i=i+1) begin : gen_wb_mux
        writeback_mux u_wb_mux (
            .alu_result(alu_result[i]),
            .mem_result(captured_lw_data[i]),
            .MemRead(load_write_pulse),
            .wb_data(wbmux_out[i])
        );
    end endgenerate

    assign wb_rd_addr     = load_write_pulse ? captured_lw_dest : rd_field;
    assign wb_active_mask = load_write_pulse ? warp_mask_reg[captured_lw_warp_id] : warp_ready_mask;
    assign wb_reg_write   = load_write_pulse ? 1'b1
                       : (RegWrite & ~MemRead & ~MemWrite & ~hold);
    //=====================================================================
    // 9. BRANCH / JUMP RESOLUTION
    //=====================================================================
    wire [15:0] lane_ok;
    generate for (i=0;i<16;i=i+1) begin : gen_lane_ok
        assign lane_ok[i] = (rs1_data[i] == rs2_data[i]) | ~warp_ready_mask[i];
    end endgenerate
    assign redirect = (Branch & &lane_ok) | Jump;
    wire signed [15:0] imm_signed = imm_field;
    assign pc_target = Jump ? imm_out : (warp_ready_pc + 16'd1 + imm_signed);

endmodule