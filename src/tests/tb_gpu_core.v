`timescale 1ns/1ps

module tb_gpu_matrix_visual;

    reg clk;
    reg rst;
    wire done;

    gpu_top dut (.clk(clk), .rst(rst), .done(done));

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Capture store results (Matrix C) from the memory line interface
    // ----------------------------------------------------------------
    reg [15:0] captured_C [0:15];
    reg        store_occurred;

    always @(posedge clk) begin
        if (!rst && dut.ms_mem_write && dut.ms_sw_word_mask != 0) begin
            for (integer j = 0; j < 16; j = j + 1) begin
                if (dut.ms_sw_word_mask[j]) begin
                    captured_C[j] <= dut.ms_sw_line_out[j][15:0];
                end
            end
            store_occurred <= 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Expected data (computed from known test patterns)
    // ----------------------------------------------------------------
    integer expected_A [0:15];
    integer expected_B [0:15];
    integer expected_C [0:15];
    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            expected_A[i] = i + 1;
            expected_B[i] = (i + 1) * 10;
            expected_C[i] = expected_A[i] + expected_B[i];
        end
    end

    // ----------------------------------------------------------------
    // Wait for done, then show matrices and check results
    // ----------------------------------------------------------------
    integer errors;
    integer r, c;
    initial begin
        rst = 1'b1;
        repeat (3) @(posedge clk);
        @(posedge clk);
        rst = 1'b0;

        wait (done == 1'b1);
        @(posedge clk);  // allow last store to settle

        if (!store_occurred) begin
            $display("FAIL: No store operation detected");
            $finish;
        end

        // ---- Display Matrix A ----
        $display("\n==================== MATRIX A ====================");
        for (r = 0; r < 4; r = r + 1) begin
            $write("  ");
            for (c = 0; c < 4; c = c + 1) begin
                $write("%4d ", expected_A[r*4 + c]);
            end
            $display("");
        end

        // ---- Display Matrix B ----
        $display("\n==================== MATRIX B ====================");
        for (r = 0; r < 4; r = r + 1) begin
            $write("  ");
            for (c = 0; c < 4; c = c + 1) begin
                $write("%4d ", expected_B[r*4 + c]);
            end
            $display("");
        end

        // ---- Display Matrix C: Expected vs Actual ----
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

        // Final pass/fail
        if (errors == 0)
            $display("\n=== Matrix Addition: PASS ===");
        else
            $display("\n=== Matrix Addition: FAIL, %0d mismatches ===", errors);

        $finish;
    end

    // Safety timeout
    initial begin
        #500000;
        $display("TIMEOUT");
        $finish;
    end

endmodule