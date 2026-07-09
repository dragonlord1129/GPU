`timescale 1ns/1ps
module tb_mul_visual_final;

    reg clk, rst;
    wire done;
    gpu_top dut (.clk(clk), .rst(rst), .done(done));

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Capture the store to line 32 (addr_base = 32)
    // ----------------------------------------------------------------
    reg [15:0] captured_C [0:15];
    reg        store_occurred;

    always @(posedge clk) begin
        if (!rst && dut.ms_mem_write && dut.ms_sw_word_mask != 0 && dut.ms_addr_out == 32) begin
            for (integer j = 0; j < 16; j = j + 1)
                if (dut.ms_sw_word_mask[j])
                    captured_C[j] <= dut.ms_sw_line_out[j][15:0];
            store_occurred <= 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Expected values
    // ----------------------------------------------------------------
    integer expected_A [0:15];
    integer expected_B [0:15];
    integer expected_C [0:15];
    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            expected_A[i] = i + 1;
            if(i % 5 == 0) expected_B[i] = 1;
            else expected_B[i] = 0;
            expected_C[i] = expected_A[i];
        end
    end

    // ----------------------------------------------------------------
    // Run simulation, then display matrices
    // ----------------------------------------------------------------
    integer errors, r, c;
    initial begin
        rst = 1'b1;
        repeat (3) @(posedge clk);
        @(posedge clk);
        rst = 1'b0;

        wait (done == 1'b1);
        @(posedge clk);  // let last store complete

        if (!store_occurred) begin
            $display("FAIL: No store to line 32 detected");
            $finish;
        end

        // ---- Matrix A ----
        $display("\n==================== MATRIX A ====================");
        for (r = 0; r < 4; r = r + 1) begin
            $write("  ");
            for (c = 0; c < 4; c = c + 1)
                $write("%4d ", expected_A[r*4 + c]);
            $display("");
        end

        // ---- Matrix B ----
        $display("\n==================== MATRIX B ====================");
        for (r = 0; r < 4; r = r + 1) begin
            $write("  ");
            for (c = 0; c < 4; c = c + 1)
                $write("%4d ", expected_B[r*4 + c]);
            $display("");
        end

        // ---- Matrix C: Expected vs Actual ----
        $display("\n==================== MATRIX C ====================");
        $display("  (Expected vs Actual)");
        $display("  +-------------+-------------+");
        $display("  |  Expected   |   Actual    |");
        $display("  +-------------+-------------+");

        errors = 0;
        for (i = 0; i < 16; i = i + 1) begin
            if (i % 4 == 0) begin
                if (i > 0) $display("  |             |             |");
                $display("  +-------------+-------------+");
            end
            $write("  | %11d | %11d |", expected_C[i], captured_C[i]);
            if (captured_C[i] !== expected_C[i]) begin
                $write("  <-- MISMATCH");
                errors = errors + 1;
            end
            $display("");
        end
        $display("  +-------------+-------------+");

        if (errors == 0)
            $display("\n=== Matrix Multiplication: PASS ===");
        else
            $display("\n=== Matrix Multiplication: FAIL, %0d mismatches ===", errors);

        $finish;
    end

    initial begin #2000000; $display("TIMEOUT"); $finish; end
    initial begin
        $dumpfile("tb_matrix_mul.vcd");
        $dumpvars(0, tb_mul_visual_final);
    end

endmodule