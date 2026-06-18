// ============================================================
// testbench_selfcheck.v -- self-checking GPU matrix multiply
// ============================================================
`timescale 1ns / 1ps
module tb_stress;
    reg         clk, reset;
    wire [15:0] debug_pc;
    wire [15:0] debug_regs [0:3][0:15][0:15];
    wire [15:0] debug_lw_out, debug_alu_result;
    wire        done;

    integer cycle_cnt;

    gpu_top #(.NUMBER_OF_WARPS(4), .NUMBER_OF_THREADS(16), .DATA_WIDTH(16)) dut (
        .clk(clk), .reset(reset),
        .lane_select(4'h0),   // not used for checking
        .debug_pc(debug_pc),
        .debug_regs(debug_regs),
        .debug_lw_out(debug_lw_out),
        .debug_alu_result(debug_alu_result),
        .done(done)
    );

    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Backdoor memory read (hierarchical peek)
    // ---------------------------------------------------------------
    function [15:0] peek;
        input [15:0] addr;
        reg [7:0] line;
        reg [3:0] bank;
        begin
            bank = addr[3:0];
            line = addr[11:4];
            case (bank)
                0: peek = dut.dmem.bank[0].u_bank.data_memory[line][15:0];
                1: peek = dut.dmem.bank[1].u_bank.data_memory[line][15:0];
                2: peek = dut.dmem.bank[2].u_bank.data_memory[line][15:0];
                3: peek = dut.dmem.bank[3].u_bank.data_memory[line][15:0];
                4: peek = dut.dmem.bank[4].u_bank.data_memory[line][15:0];
                5: peek = dut.dmem.bank[5].u_bank.data_memory[line][15:0];
                6: peek = dut.dmem.bank[6].u_bank.data_memory[line][15:0];
                7: peek = dut.dmem.bank[7].u_bank.data_memory[line][15:0];
                8: peek = dut.dmem.bank[8].u_bank.data_memory[line][15:0];
                9: peek = dut.dmem.bank[9].u_bank.data_memory[line][15:0];
                10: peek = dut.dmem.bank[10].u_bank.data_memory[line][15:0];
                11: peek = dut.dmem.bank[11].u_bank.data_memory[line][15:0];
                12: peek = dut.dmem.bank[12].u_bank.data_memory[line][15:0];
                13: peek = dut.dmem.bank[13].u_bank.data_memory[line][15:0];
                14: peek = dut.dmem.bank[14].u_bank.data_memory[line][15:0];
                15: peek = dut.dmem.bank[15].u_bank.data_memory[line][15:0];
                default: peek = 16'hxxxx;
            endcase
        end
    endfunction

    // ---------------------------------------------------------------
    // Expected C = A * B  (same data as in memfile.hex)
    // ---------------------------------------------------------------
    reg [15:0] A [0:3][0:3];
    reg [15:0] B [0:3][0:15];
    reg [15:0] C_exp [0:3][0:15];
    integer i, j, k;
    reg [31:0] temp;

    // Performance counters
    integer instr_count;
    reg     counting;

    initial begin
        // ---- Initialise expected values ----
        for (i = 0; i < 4; i = i + 1)
            for (k = 0; k < 4; k = k + 1)
                A[i][k] = i * 4 + k + 1;        // 1..16

        for (k = 0; k < 4; k = k + 1)
            for (j = 0; j < 16; j = j + 1)
                B[k][j] = k * 16 + j + 1;       // 1..64

        for (i = 0; i < 4; i = i + 1)
            for (j = 0; j < 16; j = j + 1) begin
                temp = 0;
                for (k = 0; k < 4; k = k + 1)
                    temp = temp + A[i][k] * B[k][j];
                C_exp[i][j] = temp[15:0];
            end

        // ---- Simulation flow ----
        clk = 0;
        reset = 1;
        cycle_cnt = 0;
        instr_count = 0;
        counting = 0;

        #15;                                     // hold reset for ~1.5 cycles
        reset = 0;
        @(negedge clk);                          // wait until clock low after deassert
        // Force all warp PCs to 0 (they default to 0,16,32,48)
        dut.warp_inst.WARP_PC[0] = 16'h0000;
        dut.warp_inst.WARP_PC[1] = 16'h0000;
        dut.warp_inst.WARP_PC[2] = 16'h0000;
        dut.warp_inst.WARP_PC[3] = 16'h0000;
        // (finished flags are already 0 after reset)

        @(posedge clk);
        counting = 1;                            // start counting performance

        // Wait for done or timeout
        while (!done && cycle_cnt < 50000) begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;
            if (dut.running) instr_count = instr_count + 1;
        end

        counting = 0;

        // ---- Check results ----
        if (done) begin
            integer errors;
            errors = 0;
            for (i = 0; i < 4; i = i + 1)
                for (j = 0; j < 16; j = j + 1) begin
                    if (peek(128 + i*16 + j) !== C_exp[i][j]) begin
                        $display("ERROR: C[%0d][%0d] = %h, expected %h",
                                 i, j, peek(128 + i*16 + j), C_exp[i][j]);
                        errors = errors + 1;
                    end
                end

            $display("===========================================");
            $display(" GPU Matrix Multiply Self-Check Test");
            $display("===========================================");
            $display(" Total cycles:          %0d", cycle_cnt);
            $display(" Total instructions:     %0d", instr_count);
            $display(" IPC:                   %0.3f", 
                     (instr_count > 0) ? $itor(instr_count)/$itor(cycle_cnt) : 0.0);
            $display(" MACs computed:         256 (4x4 * 4x16)");
            $display(" Throughput (MAC/cycle):%0.3f",
                     (cycle_cnt > 0) ? 256.0 / cycle_cnt : 0.0);
            if (errors == 0) begin
                $display(" Result check: PASS");
                $display("===========================================");
                $finish;
            end else begin
                $display(" Result check: FAIL (%0d errors)", errors);
                $display("===========================================");
                $finish;
            end
        end else begin
            $display("FAIL: Timeout after %0d cycles", cycle_cnt);
            $finish;
        end
    end

    // Optional: print PC and instruction each cycle (for debug)
    always @(posedge clk) begin
        if (dut.running && dut.warp_ready_mask[0])
            $display("Cycle %0d: PC = %h, Instr = %h", cycle_cnt, debug_pc, dut.instr);
    end
endmodule