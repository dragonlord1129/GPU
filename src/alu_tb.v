module alu_tb;

    // ─────────────────────────────────────────────────────────
    // Parameters
    // ─────────────────────────────────────────────────────────
    parameter WIDTH     = 32;
    parameter ALU_WIDTH = 4;

    // ─────────────────────────────────────────────────────────
    // DUT Inputs
    // ─────────────────────────────────────────────────────────
    reg  [WIDTH-1:0]     A, B;
    reg  [ALU_WIDTH-1:0] ALUControl;

    // ─────────────────────────────────────────────────────────
    // DUT Outputs
    // ─────────────────────────────────────────────────────────
    wire [WIDTH-1:0] result;
    wire carry;
    wire zero;
    wire overflow;
    wire negative;
    wire divide_by_zero;

    // ─────────────────────────────────────────────────────────
    // Signed aliases for GTKWave
    // ─────────────────────────────────────────────────────────
    wire signed [WIDTH-1:0] A_signed;
    wire signed [WIDTH-1:0] B_signed;
    wire signed [WIDTH-1:0] result_signed;

    assign A_signed      = A;
    assign B_signed      = B;
    assign result_signed = result;

    // ─────────────────────────────────────────────────────────
    // DUT
    // ─────────────────────────────────────────────────────────
    alu #(
        .WIDTH(WIDTH),
        .ALU_WIDTH(ALU_WIDTH)
    ) dut (
        .A(A),
        .B(B),
        .ALUControl(ALUControl),
        .result(result),
        .carry(carry),
        .zero(zero),
        .overflow(overflow),
        .negative(negative),
        .divide_by_zero(divide_by_zero)
    );

    // ─────────────────────────────────────────────────────────
    // VCD Dump
    // ─────────────────────────────────────────────────────────
    initial begin
        $dumpfile("alu_wave.vcd");
        $dumpvars(0, alu_tb);

        $display("========================================");
        $display(" GTKWave:");
        $display(" Right click signal ->");
        $display(" Data Format -> Signed Decimal");
        $display("========================================");
    end

    // ─────────────────────────────────────────────────────────
    // Counters
    // ─────────────────────────────────────────────────────────
    integer pass_count;
    integer fail_count;

    // ─────────────────────────────────────────────────────────
    // Generic Check Task
    // ─────────────────────────────────────────────────────────
    task check;
        input [WIDTH-1:0] exp_result;
        input             exp_zero;
        input             exp_negative;
        input             exp_overflow;
        input [127:0]     test_name;

        begin
            #5;

            if ((result    !== exp_result)   ||
                (zero      !== exp_zero)     ||
                (negative  !== exp_negative) ||
                (overflow  !== exp_overflow)) begin

                $display("FAIL [%0s]", test_name);
                $display("  A        = %0d", $signed(A));
                $display("  B        = %0d", $signed(B));
                $display("  CTRL     = %b", ALUControl);

                $display("  RESULT   = %0d (exp %0d)",
                         $signed(result),
                         $signed(exp_result));

                $display("  ZERO     = %b (exp %b)",
                         zero, exp_zero);

                $display("  NEGATIVE = %b (exp %b)",
                         negative, exp_negative);

                $display("  OVERFLOW = %b (exp %b)",
                         overflow, exp_overflow);

                fail_count = fail_count + 1;

            end else begin

                $display("PASS [%0s] RESULT=%0d",
                         test_name,
                         $signed(result));

                pass_count = pass_count + 1;
            end

            #5;
        end
    endtask

    // ─────────────────────────────────────────────────────────
    // Division Check Task
    // ─────────────────────────────────────────────────────────
    task check_div;
        input [WIDTH-1:0] exp_result;
        input             exp_dbz;
        input [127:0]     test_name;

        begin
            #5;

            if ((result !== exp_result) ||
                (divide_by_zero !== exp_dbz)) begin

                $display("FAIL [%0s]", test_name);

                $display("  A      = %0d", $signed(A));
                $display("  B      = %0d", $signed(B));
                $display("  CTRL   = %b", ALUControl);

                $display("  RESULT = %0d (exp %0d)",
                         $signed(result),
                         $signed(exp_result));

                $display("  DBZ    = %b (exp %b)",
                         divide_by_zero,
                         exp_dbz);

                fail_count = fail_count + 1;

            end else begin

                $display("PASS [%0s] RESULT=%0d",
                         test_name,
                         $signed(result));

                pass_count = pass_count + 1;
            end

            #5;
        end
    endtask

    // ─────────────────────────────────────────────────────────
    // Test Stimulus
    // ─────────────────────────────────────────────────────────
    initial begin

        pass_count = 0;
        fail_count = 0;

        $display("\n========================================");
        $display(" ALU TESTBENCH");
        $display(" WIDTH = %0d", WIDTH);
        $display("========================================");

        // ====================================================
        // ADD
        // ====================================================
        $display("\n--- ADD ---");

        A = 32'd15;
        B = 32'd10;
        ALUControl = 4'b0000;
        check(32'd25, 0, 0, 0, "ADD basic");

        A = 32'd0;
        B = 32'd0;
        ALUControl = 4'b0000;
        check(32'd0, 1, 0, 0, "ADD zero");

        A = 32'h7FFF_FFFF;
        B = 32'd1;
        ALUControl = 4'b0000;
        check(32'h8000_0000, 0, 1, 1, "ADD overflow");

        // ====================================================
        // SUB
        // ====================================================
        $display("\n--- SUB ---");

        A = 32'd20;
        B = 32'd5;
        ALUControl = 4'b0001;
        check(32'd15, 0, 0, 0, "SUB basic");

        A = 32'd5;
        B = 32'd5;
        ALUControl = 4'b0001;
        check(32'd0, 1, 0, 0, "SUB zero");

        A = 32'd3;
        B = 32'd10;
        ALUControl = 4'b0001;
        check(32'hFFFF_FFF9, 0, 1, 0, "SUB negative");

        A = 32'h8000_0000;
        B = 32'd1;
        ALUControl = 4'b0001;
        check(32'h7FFF_FFFF, 0, 0, 1, "SUB overflow");

        // ====================================================
        // AND
        // ====================================================
        $display("\n--- AND ---");

        A = 32'hFF00_FF00;
        B = 32'hF0F0_F0F0;
        ALUControl = 4'b0010;
        check(32'hF000_F000, 0, 1, 0, "AND pattern");

        A = 32'hAAAA_AAAA;
        B = 32'h5555_5555;
        ALUControl = 4'b0010;
        check(32'h0000_0000, 1, 0, 0, "AND zero");

        // ====================================================
        // OR
        // ====================================================
        $display("\n--- OR ---");

        A = 32'hFF00_0000;
        B = 32'h00FF_0000;
        ALUControl = 4'b0011;
        check(32'hFFFF_0000, 0, 1, 0, "OR combine");

        A = 32'h0;
        B = 32'h0;
        ALUControl = 4'b0011;
        check(32'h0, 1, 0, 0, "OR zero");

        // ====================================================
        // XOR
        // ====================================================
        $display("\n--- XOR ---");

        A = 32'hFFFF_FFFF;
        B = 32'hFFFF_FFFF;
        ALUControl = 4'b0100;
        check(32'h0000_0000, 1, 0, 0, "XOR same");

        A = 32'hAAAA_AAAA;
        B = 32'h5555_5555;
        ALUControl = 4'b0100;
        check(32'hFFFF_FFFF, 0, 1, 0, "XOR alternating");

        // ====================================================
        // MUL LOW
        // ====================================================
        $display("\n--- MUL LOW ---");

        A = 32'd6;
        B = 32'd7;
        ALUControl = 4'b0101;
        check(32'd42, 0, 0, 0, "MUL 6x7");

        A = 32'd0;
        B = 32'd999;
        ALUControl = 4'b0101;
        check(32'd0, 1, 0, 0, "MUL by zero");

        A = -32'd3;
        B = 32'd4;
        ALUControl = 4'b0101;
        check(-32'd12, 0, 1, 0, "MUL neg*pos");

        A = -32'd5;
        B = -32'd5;
        ALUControl = 4'b0101;
        check(32'd25, 0, 0, 0, "MUL neg*neg");

        // ====================================================
        // DIV QUOTIENT
        // ====================================================
        $display("\n--- DIV QUOTIENT ---");

        A = 32'd20;
        B = 32'd4;
        ALUControl = 4'b0111;
        check_div(32'd5, 0, "DIV 20/4");

        A = 32'd7;
        B = 32'd2;
        ALUControl = 4'b0111;
        check_div(32'd3, 0, "DIV 7/2");

        A = -32'd20;
        B = 32'd4;
        ALUControl = 4'b0111;
        check_div(-32'd5, 0, "DIV -20/4");

        A = 32'd99;
        B = 32'd0;
        ALUControl = 4'b0111;
        check_div(32'd0, 1, "DIV by zero");

        // ====================================================
        // REMAINDER
        // ====================================================
        $display("\n--- REMAINDER ---");

        A = 32'd20;
        B = 32'd6;
        ALUControl = 4'b1000;
        check(32'd2, 0, 0, 0, "REM 20%6");

        A = -32'd20;
        B = 32'd6;
        ALUControl = 4'b1000;
        check(-32'd2, 0, 1, 0, "REM -20%6");

        // ====================================================
        // SLT
        // ====================================================
        $display("\n--- SLT ---");

        A = 32'd3;
        B = 32'd10;
        ALUControl = 4'b1001;
        check(32'd1, 0, 0, 0, "SLT 3<10");

        A = 32'd10;
        B = 32'd3;
        ALUControl = 4'b1001;
        check(32'd0, 1, 0, 0, "SLT 10>=3");

        A = 32'd5;
        B = 32'd5;
        ALUControl = 4'b1001;
        check(32'd0, 1, 0, 0, "SLT equal");

        A = -32'd1;
        B = 32'd0;
        ALUControl = 4'b1001;
        check(32'd1, 0, 0, 0, "SLT -1<0");

        A = 32'h8000_0000;
        B = 32'd0;
        ALUControl = 4'b1001;
        check(32'd1, 0, 0, 0, "SLT INT_MIN");

        // ====================================================
        // Summary
        // ====================================================
        $display("\n========================================");
        $display(" TEST SUMMARY");
        $display(" PASSED = %0d", pass_count);
        $display(" FAILED = %0d", fail_count);
        $display("========================================");

        #10;
        $finish;
    end

endmodule