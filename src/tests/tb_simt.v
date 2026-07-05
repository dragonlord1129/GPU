// ============================================================
// TESTBENCH: tb_simt (FINAL – holds scheduler during preload)
// ============================================================

`timescale 1ns / 1ps

module tb_simt;

    // -----------------------------------------------------------------
    // Parameters and signals
    // -----------------------------------------------------------------
    localparam LANES = 16;
    localparam WIDTH = 16;
    localparam NUM_WARPS = 4;

    reg clk;
    reg rst;

    wire [1:0]  current_warp_id;
    wire [15:0] warp_ready;
    wire [15:0] warp_ready_mask;
    wire        running;
    wire        done;

    wire [WIDTH-1:0] rs1_data [0:LANES-1];
    wire [WIDTH-1:0] rs2_data [0:LANES-1];
    reg  [WIDTH-1:0] write_data [0:LANES-1];
    reg  [3:0]       rd_addr;
    reg  [3:0]       rs1_addr;
    reg  [3:0]       rs2_addr;
    reg              reg_write;

    reg  [3:0] opcode;
    wire [3:0] ALUControl;

    wire [WIDTH-1:0] alu_result [0:LANES-1];

    reg         mem_req;
    reg         mem_done;
    reg  [1:0]  warp_id_from_ms;
    reg         halt;
    reg         hold;        // <-- now driven from testbench
    reg         redirect;
    reg  [15:0] pc_target;

    reg [15:0] instr_mem [0:63];
    reg [15:0] data_mem [0:63];

    reg [15:0] current_pc;
    reg [3:0]  current_opcode;
    reg [3:0]  current_rd;
    reg [3:0]  current_rs1;
    reg [3:0]  current_rs2;
    reg        current_reg_write;
    reg        current_mem_op;
    reg        current_halt;

    reg [3:0]  mem_cnt;
    reg        mem_pending;
    reg [3:0]  mem_rd;
    reg [1:0]  mem_warp_id;

    integer lane;
    integer reg_idx;
    integer expected_mul;

    // -----------------------------------------------------------------
    // Instantiate modules
    // -----------------------------------------------------------------
    warp_scheduler #(
        .NUMBER_OF_WARPS(NUM_WARPS)
    ) u_scheduler (
        .clk(clk),
        .rst(rst),
        .mem_req(mem_req),
        .mem_done(mem_done),
        .warp_id_from_ms(warp_id_from_ms),
        .halt(halt),
        .hold(hold),        // connected
        .redirect(redirect),
        .pc_target(pc_target),
        .warp_id_to_ms(),
        .warp_ready(warp_ready),
        .warp_ready_mask(warp_ready_mask),
        .current_warp_id(current_warp_id),
        .running(running),
        .done(done)
    );

    alu_control u_alu_ctrl (
        .opcode(opcode),
        .ALUControl(ALUControl)
    );

    simt_alu #(
        .LANES(LANES),
        .WIDTH(WIDTH)
    ) u_simt_alu (
        .A(rs1_data),
        .B(rs2_data),
        .ALUControl(ALUControl),
        .Result(alu_result)
    );

    reg_file_simt #(
        .DATA_WIDTH(WIDTH),
        .NUM_REGS(16),
        .LANES(LANES)
    ) u_regfile (
        .clk(clk),
        .reset(rst),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rd_addr(rd_addr),
        .active_mask(warp_ready_mask),
        .write_data(write_data),
        .reg_write(reg_write),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    // -----------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------
    always #5 clk = ~clk;

    // -----------------------------------------------------------------
    // Instruction memory initialisation
    // -----------------------------------------------------------------
    initial begin
        // Warp 0
        instr_mem[16'h0000] = {4'h0, 4'h4, 4'h2, 4'h3};   // ADD  r4, r2, r3
        instr_mem[16'h0001] = {4'h6, 4'h0, 4'h0, 4'h0};   // MEM (stall)
        instr_mem[16'h0002] = {4'h1, 4'h5, 4'h4, 4'h2};   // SUB  r5, r4, r2
        instr_mem[16'h0003] = {4'h5, 4'h6, 4'h5, 4'h6};   // MUL  r6, r5, r6 (low)
        instr_mem[16'h0004] = {4'hF, 4'h0, 4'h0, 4'h0};   // HALT

        // Warp 1
        instr_mem[16'h0010] = {4'h2, 4'h1, 4'h7, 4'h8};   // AND  r1, r7, r8
        instr_mem[16'h0011] = {4'h3, 4'h2, 4'h9, 4'hA};   // OR   r2, r9, r10
        instr_mem[16'h0012] = {4'h4, 4'h3, 4'hB, 4'hC};   // XOR  r3, r11, r12
        instr_mem[16'h0013] = {4'hF, 4'h0, 4'h0, 4'h0};   // HALT

        // Warp 2 & 3 idle
        instr_mem[16'h0020] = {4'hF, 4'h0, 4'h0, 4'h0};
        instr_mem[16'h0030] = {4'hF, 4'h0, 4'h0, 4'h0};

        for (integer i = 0; i < 64; i++) data_mem[i] = i * 2;
    end

    // -----------------------------------------------------------------
    // Main test procedure
    // -----------------------------------------------------------------
    initial begin
        clk = 0;
        rst = 1;
        mem_req = 0;
        mem_done = 0;
        warp_id_from_ms = 0;
        halt = 0;
        hold = 0;          // start with hold deasserted
        redirect = 0;
        pc_target = 0;
        reg_write = 0;
        rd_addr = 0;
        rs1_addr = 0;
        rs2_addr = 0;
        mem_cnt = 0;
        mem_pending = 0;
        mem_warp_id = 0;

        // Reset
        #20;
        rst = 0;
        #10;

        // -------------------------------------------------------------
        // PAUSE SCHEDULER AND PRELOAD REGISTERS
        // -------------------------------------------------------------
        hold = 1;   // freeze scheduler – no instructions fetched

        // Force active_mask to all 1s for writes
        force u_regfile.active_mask = 16'hFFFF;

        for (reg_idx = 2; reg_idx <= 12; reg_idx = reg_idx + 1) begin
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                case (reg_idx)
                    2:  write_data[lane] = lane + 1;
                    3:  write_data[lane] = (lane + 1) * 2;
                    4:  write_data[lane] = lane + 3;
                    5:  write_data[lane] = lane + 5;
                    6:  write_data[lane] = lane + 6;
                    7:  write_data[lane] = lane + 7;
                    8:  write_data[lane] = lane + 8;
                    9:  write_data[lane] = lane + 9;
                    10: write_data[lane] = lane + 10;
                    11: write_data[lane] = lane + 11;
                    12: write_data[lane] = lane + 12;
                    default: write_data[lane] = 0;
                endcase
            end
            rd_addr = reg_idx[3:0];
            reg_write = 1;
            @(posedge clk);
        end
        reg_write = 0;
        release u_regfile.active_mask;
        hold = 0;   // resume scheduler

        // -------------------------------------------------------------
        // Wait for all warps to finish
        // -------------------------------------------------------------
        wait (done == 1);
        #100;

        // -------------------------------------------------------------
        // Verify results
        // -------------------------------------------------------------
        $display("\n=== Simulation finished, checking results ===");

        // Warp 0: r4, r5, r6
        $display("\n--- Warp 0 results (r4, r5, r6) ---");
        for (lane = 0; lane < LANES; lane = lane + 1) begin
            rs1_addr = 4;
            #1;
            if (rs1_data[lane] !== 3*(lane+1))
                $error("Lane %0d: r4 expected %0d, got %0d", lane, 3*(lane+1), rs1_data[lane]);
            else
                $display("Lane %0d: r4 = %0d (OK)", lane, rs1_data[lane]);

            rs1_addr = 5;
            #1;
            if (rs1_data[lane] !== 2*(lane+1))
                $error("Lane %0d: r5 expected %0d, got %0d", lane, 2*(lane+1), rs1_data[lane]);
            else
                $display("Lane %0d: r5 = %0d (OK)", lane, rs1_data[lane]);

            expected_mul = (2*(lane+1)) * (lane+6) & 16'hFFFF;
            rs1_addr = 6;
            #1;
            if (rs1_data[lane] !== expected_mul)
                $error("Lane %0d: r6 expected %0d, got %0d", lane, expected_mul, rs1_data[lane]);
            else
                $display("Lane %0d: r6 = %0d (OK)", lane, rs1_data[lane]);
        end

        // Warp 1: r1, r2, r3
        $display("\n--- Warp 1 results (r1, r2, r3) ---");
        for (lane = 0; lane < LANES; lane = lane + 1) begin
            rs1_addr = 1;
            #1;
            if (rs1_data[lane] !== ((lane+7) & (lane+8)))
                $error("Lane %0d: r1 expected %0d, got %0d", lane, (lane+7)&(lane+8), rs1_data[lane]);
            else
                $display("Lane %0d: r1 = %0d (OK)", lane, rs1_data[lane]);

            rs1_addr = 2;
            #1;
            if (rs1_data[lane] !== ((lane+9) | (lane+10)))
                $error("Lane %0d: r2 expected %0d, got %0d", lane, (lane+9)|(lane+10), rs1_data[lane]);
            else
                $display("Lane %0d: r2 = %0d (OK)", lane, rs1_data[lane]);

            rs1_addr = 3;
            #1;
            if (rs1_data[lane] !== ((lane+11) ^ (lane+12)))
                $error("Lane %0d: r3 expected %0d, got %0d", lane, (lane+11)^(lane+12), rs1_data[lane]);
            else
                $display("Lane %0d: r3 = %0d (OK)", lane, rs1_data[lane]);
        end

        $display("\n=== All checks completed ===");
        $finish;
    end

    // -----------------------------------------------------------------
    // Pipeline execution logic
    // -----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            mem_pending <= 0;
            mem_cnt <= 0;
            mem_req <= 0;
            mem_done <= 0;
            halt <= 0;
            redirect <= 0;
            reg_write <= 0;
            mem_warp_id <= 0;
        end else begin
            // Defaults – these are overridden by the pipeline decisions below
            mem_req <= 0;
            mem_done <= 0;
            halt <= 0;
            redirect <= 0;
            reg_write <= 0;

            // 1. Fetch current instruction (PC from scheduler)
            current_pc = warp_ready;
            current_opcode = instr_mem[current_pc][15:12];
            current_rd     = instr_mem[current_pc][11:8];
            current_rs1    = instr_mem[current_pc][7:4];
            current_rs2    = instr_mem[current_pc][3:0];

            // 2. Decode
            current_reg_write = (current_opcode != 4'h8 && current_opcode != 4'hF);
            current_mem_op    = (current_opcode == 4'h6 || current_opcode == 4'h7);
            current_halt      = (current_opcode == 4'hF);

            // 3. Set register read addresses (combinational)
            rs1_addr <= current_rs1;
            rs2_addr <= current_rs2;

            // 4. Writeback
            if (current_reg_write) begin
                rd_addr <= current_rd;
                for (lane = 0; lane < LANES; lane = lane + 1)
                    write_data[lane] <= alu_result[lane];
                reg_write <= 1;
            end

            // 5. Memory request handling
            if (current_mem_op && !mem_pending) begin
                mem_req <= 1;
                mem_pending <= 1;
                mem_cnt <= 0;
                mem_rd <= current_rd;
                mem_warp_id <= current_warp_id;
            end

            if (mem_pending) begin
                mem_cnt <= mem_cnt + 1;
                if (mem_cnt == 4) begin
                    mem_done <= 1;
                    warp_id_from_ms <= mem_warp_id;
                    mem_pending <= 0;
                end
            end

            // 6. Halt
            if (current_halt)
                halt <= 1;
        end
    end

endmodule