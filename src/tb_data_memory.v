`timescale 1ns/1ps

module tb_data_memory;

reg clk;
reg writeEnable;
reg [7:0] A;
reg [31:0] writeData;
wire [31:0] RD;

// DUT with parameters
data_memory #(
    .ADDR_WIDTH(8),
    .DEPTH(256)
) uut (
    .A(A),
    .writeData(writeData),
    .clk(clk),
    .writeEnable(writeEnable),
    .RD(RD)
);

// clock
always #5 clk = ~clk;

initial begin
    clk = 0;
    writeEnable = 0;
    A = 0;
    writeData = 0;

    $display("===== PARAMETERIZED MEMORY TEST =====");

    // -------------------------
    // TEST 1: Write & Read
    // -------------------------
    @(negedge clk);
    A = 8'd5;
    writeData = 32'hAAAA5555;
    writeEnable = 1;

    @(negedge clk);
    writeEnable = 0;

    #1;
    if (RD == 32'hAAAA5555)
        $display("PASS: addr 5 write/read");
    else
        $display("FAIL: RD = %h", RD);

    // -------------------------
    // TEST 2: Another address
    // -------------------------
    @(negedge clk);
    A = 8'd100;
    writeData = 32'h12345678;
    writeEnable = 1;

    @(negedge clk);
    writeEnable = 0;

    #1;
    if (RD == 32'h12345678)
        $display("PASS: addr 100 write/read");
    else
        $display("FAIL: RD = %h", RD);

    // -------------------------
    // TEST 3: Retention check
    // -------------------------
    A = 8'd5;
    #1;
    if (RD == 32'hAAAA5555)
        $display("PASS: retention check");
    else
        $display("FAIL: corrupted memory");

    // -------------------------
    // TEST 4: Overwrite
    // -------------------------
    @(negedge clk);
    A = 8'd5;
    writeData = 32'hCAFEBABE;
    writeEnable = 1;

    @(negedge clk);
    writeEnable = 0;

    #1;
    if (RD == 32'hCAFEBABE)
        $display("PASS: overwrite test");
    else
        $display("FAIL: overwrite failed");

    // -------------------------
    // RANDOM STRESS TEST
    // -------------------------
    repeat (10) begin
        @(negedge clk);
        A = $random % 256;
        writeData = $random;
        writeEnable = 1;
    end

    writeEnable = 0;

    $display("===== RANDOM TEST DONE =====");

    #10;
    $finish;
end

endmodule