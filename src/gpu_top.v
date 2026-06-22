module gpu_top(
    input clk,
    input rst
);

    // ==========================================================
    // Warp Scheduler
    // ==========================================================

    wire [15:0] pc;
    wire [1:0] current_warp;

    wire mem_req;
    wire mem_done;

    wire halt;
    wire redirect;

    wire [15:0] pc_target;

    warp_scheduler WS(
        .clk(clk),
        .rst(rst),

        .mem_req(mem_req),
        .mem_done(mem_done),

        .warp_id_from_ms(warp_id_to_ws),

        .halt(halt),
        .hold(1'b0),

        .redirect(redirect),
        .pc_target(pc_target),

        .warp_id_to_ms(),
        .warp_ready(pc),
        .warp_ready_mask(),

        .current_warp_id(current_warp),

        .running(),
        .done()
    );

    // ==========================================================
    // Instruction Fetch
    // ==========================================================

    wire [31:0] instruction;

    instruction_memory IMEM(
        .A(pc),
        .RD(instruction)
    );

    // ==========================================================
    // Decode
    // ==========================================================

    wire [3:0] opcode;
    wire [3:0] rd;
    wire [3:0] rs1;
    wire [3:0] rs2;
    wire [15:0] imm;

    instruction_decoder DEC(
        .instruction(instruction),

        .opcode(opcode),
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),
        .imm(imm)
    );

    // ==========================================================
    // Main Control
    // ==========================================================

    wire RegWrite;
    wire MemRead;
    wire MemWrite;
    wire Branch;
    wire Jump;
    wire Halt;
    wire ALUSrc;

    main_control CTRL(
        .opcode(opcode),

        .RegWrite(RegWrite),
        .MemRead(MemRead),
        .MemWrite(MemWrite),
        .Branch(Branch),
        .Jump(Jump),
        .Halt(Halt),
        .ALUSrc(ALUSrc)
    );

    assign halt = Halt;

    // ==========================================================
    // ALU Control
    // ==========================================================

    wire [3:0] ALUControl;

    alu_control ALUCTRL(
        .opcode(opcode),
        .ALUControl(ALUControl)
    );

    // ==========================================================
    // Register File
    // ==========================================================

    wire [15:0] rs1_data;
    wire [15:0] rs2_data;

    wire [15:0] wb_data;

    reg_file RF(
        .clk(clk),
        .reset(rst),

        .A1(rs1),
        .A2(rs2),
        .A3(rd),

        .RS1(rs1_data),
        .RS2(rs2_data),

        .block_idx(16'd0),
        .block_dim(16'd16),
        .thread_idx(16'd0),

        .WD(wb_data),

        .we(RegWrite),
        .reg_en(1'b1)
    );

    // ==========================================================
    // Operand Select
    // ==========================================================

    wire [15:0] operand_b;

    assign operand_b =
            ALUSrc ?
            imm :
            rs2_data;

    // ==========================================================
    // ALU
    // ==========================================================

    wire [31:0] alu_result;

    alu #(
        .WIDTH(16)
    ) ALU0(
        .A(rs1_data),
        .B(operand_b),

        .ALUControl(ALUControl),

        .result(alu_result),

        .carry(),
        .zero(),
        .overflow(),
        .negative(),
        .divide_by_zero()
    );

    // ==========================================================
    // Memory Request Generator
    // ==========================================================

    wire [3:0] request;

    memory_request_generator MRG(
        .MemRead(MemRead),
        .MemWrite(MemWrite),

        .mem_req(mem_req),
        .request(request)
    );

    // ==========================================================
    // Memory Scheduler
    // ==========================================================

    wire [15:0] lw_out [0:15];

    wire [15:0] addr_in [0:15];
    wire [15:0] sw_out  [0:15];

    genvar i;

    generate
        for(i=0;i<16;i=i+1) begin

            assign addr_in[i] = alu_result[15:0];
            assign sw_out[i]  = rs2_data;

        end
    endgenerate

    wire [15:0] addr_base;
    wire [15:0] sw_line_out [0:15];
    wire [15:0] lw_line_in  [0:15];
    wire [15:0] active_mask;

    assign active_mask = 16'hFFFF;

    wire [1:0] warp_id_to_ws;
    wire [1:0] lw_warp_id;

    wire lw_ready;

    wire [3:0] lw_destination_out;

    memory_scheduler MS(
        .clk(clk),
        .reset(rst),

        .request(request),

        .active_mask(active_mask),

        .addr_in(addr_in),
        .sw_out(sw_out),

        .lw_out(lw_out),

        .stall(),

        .mem_write(),

        .mem_req(mem_req),

        .warp_id_from_ws(current_warp),

        .mem_done(mem_done),

        .warp_id_to_ws(warp_id_to_ws),

        .lw_destination(rd),

        .lw_destination_out(lw_destination_out),

        .lw_line_in(lw_line_in),

        .addr_out(addr_base),

        .sw_line_out(sw_line_out),

        .sw_word_mask(),

        .lw_warp_id(lw_warp_id),

        .lw_ready(lw_ready)
    );

    // ==========================================================
    // Data Memory
    // ==========================================================

    data_memory_line DMEM(
        .clk(clk),

        .mem_write(MemWrite),

        .addr_base(addr_base),

        .sw_word_mask(16'hFFFF),

        .sw_line_out(sw_line_out),

        .lw_line_in(lw_line_in)
    );

    // ==========================================================
    // Writeback
    // ==========================================================

    writeback_mux WBM(
        .alu_result(alu_result[15:0]),
        .mem_result(lw_out[0]),
        .MemRead(MemRead),

        .wb_data(wb_data)
    );

    // ==========================================================
    // Branch Logic
    // ==========================================================

    assign redirect =
            Jump |
            (Branch && (rs1_data == rs2_data));

    assign pc_target = imm;

endmodule