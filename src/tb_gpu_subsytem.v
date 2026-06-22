`timescale 1ns/1ps

module tb_gpu_subsystem;

    //---------------------------------------------
    // Clock / Reset
    //---------------------------------------------

    reg clk;
    reg reset;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //---------------------------------------------
    // ALU DUT
    //---------------------------------------------

    reg  [31:0] alu_A;
    reg  [31:0] alu_B;
    reg  [3:0]  alu_ctrl;

    wire [31:0] alu_result;
    wire alu_carry;
    wire alu_zero;
    wire alu_overflow;
    wire alu_negative;
    wire alu_div0;

    alu alu_dut (
        .A(alu_A),
        .B(alu_B),
        .ALUControl(alu_ctrl),
        .result(alu_result),
        .carry(alu_carry),
        .zero(alu_zero),
        .overflow(alu_overflow),
        .negative(alu_negative),
        .divide_by_zero(alu_div0)
    );

    //---------------------------------------------
    // REGFILE DUT
    //---------------------------------------------

    reg [3:0] rf_A1;
    reg [3:0] rf_A2;
    reg [3:0] rf_A3;
    reg [15:0] rf_WD;
    reg rf_we;

    wire [15:0] rf_RS1;
    wire [15:0] rf_RS2;

    reg_file rf_dut(
        .clk(clk),
        .reset(reset),
        .A1(rf_A1),
        .A2(rf_A2),
        .A3(rf_A3),
        .RS1(rf_RS1),
        .RS2(rf_RS2),
        .block_idx(16'd1),
        .block_dim(16'd16),
        .thread_idx(16'd5),
        .WD(rf_WD),
        .we(rf_we),
        .reg_en(1'b1)
    );

    //---------------------------------------------
    // MEMORY SCHEDULER + MEMORY
    //---------------------------------------------

    reg [3:0] request;
    reg [15:0] active_mask;

    reg [15:0] addr_in [0:15];
    reg [15:0] sw_out  [0:15];

    wire [15:0] lw_out [0:15];

    reg mem_req;
    reg [1:0] warp_id_from_ws;

    wire mem_done;
    wire [1:0] warp_id_to_ws;

    reg [3:0] lw_destination;
    wire [3:0] lw_destination_out;

    wire [15:0] addr_out;

    wire [15:0] sw_line_out [0:15];
    wire [15:0] lw_line_in  [0:15];

    wire [15:0] sw_word_mask;

    wire mem_write;
    wire stall;

    wire [1:0] lw_warp_id;
    wire lw_ready;

    memory_scheduler ms_dut(
        .clk(clk),
        .reset(reset),
        .request(request),
        .active_mask(active_mask),
        .addr_in(addr_in),
        .sw_out(sw_out),
        .lw_out(lw_out),
        .stall(stall),
        .mem_write(mem_write),
        .mem_req(mem_req),
        .warp_id_from_ws(warp_id_from_ws),
        .mem_done(mem_done),
        .warp_id_to_ws(warp_id_to_ws),
        .lw_destination(lw_destination),
        .lw_destination_out(lw_destination_out),
        .lw_line_in(lw_line_in),
        .addr_out(addr_out),
        .sw_line_out(sw_line_out),
        .sw_word_mask(sw_word_mask),
        .lw_warp_id(lw_warp_id),
        .lw_ready(lw_ready)
    );

    data_memory_line mem_dut(
        .clk(clk),
        .mem_write(mem_write),
        .addr_base(addr_out),
        .sw_word_mask(sw_word_mask),
        .sw_line_out(sw_line_out),
        .lw_line_in(lw_line_in)
    );

    //---------------------------------------------
    // WARP SCHEDULER
    //---------------------------------------------

    reg halt;
    reg hold;
    reg redirect;
    reg [15:0] pc_target;

    wire [1:0] current_warp_id;
    wire [15:0] warp_ready;
    wire [15:0] warp_ready_mask;
    wire [1:0] warp_id_to_ms;
    wire running;
    wire done;

    warp_scheduler ws_dut(
        .clk(clk),
        .rst(reset),
        .mem_req(mem_req),
        .mem_done(mem_done),
        .warp_id_from_ms(warp_id_to_ws),
        .halt(halt),
        .hold(hold),
        .redirect(redirect),
        .pc_target(pc_target),
        .warp_id_to_ms(warp_id_to_ms),
        .warp_ready(warp_ready),
        .warp_ready_mask(warp_ready_mask),
        .current_warp_id(current_warp_id),
        .running(running),
        .done(done)
    );

    integer i;
    
    //---------------------------------------------
    // TEST SEQUENCE
    //---------------------------------------------

    initial begin

        reset = 1;
        mem_req = 0;
        rf_we = 0;
        halt = 0;
        hold = 0;
        redirect = 0;

        #40;
        reset = 0;

        //-----------------------------------------
        // ALU TESTS
        //-----------------------------------------

        alu_A = 25;
        alu_B = 17;

        alu_ctrl = 4'b0000;
        #1;
        if(alu_result != 42) $fatal(1, "ADD FAIL");

        alu_ctrl = 4'b0001;
        #1;
        if(alu_result != 8) $fatal(1, "SUB FAIL");

        alu_ctrl = 4'b0101;
        #1;
        if(alu_result != 425) $fatal(1, "MUL FAIL");

        alu_ctrl = 4'b0111;
        #1;
        if(alu_result != 1) $fatal(1, "DIV FAIL");

        alu_A = 5;
        alu_B = 10;
        alu_ctrl = 4'b1001;
        #1;
        if(alu_result != 1) $fatal(1, "SLT FAIL");

        alu_A = 100;
        alu_B = 0;
        alu_ctrl = 4'b0111;
        #1;
        if(!alu_div0) $fatal(1, "DIV0 FAIL");

        $display("ALU PASS");

        //-----------------------------------------
        // REGFILE TEST
        //-----------------------------------------

        @(posedge clk);

        rf_A3 <= 4'd3;
        rf_WD <= 16'h1234;
        rf_we <= 1;

        @(posedge clk);

        rf_we <= 0;

        rf_A1 <= 4'd3;

        #1;

        if(rf_RS1 != 16'h1234)
            $fatal(1, "REGFILE FAIL");

        $display("REGFILE PASS");

        //-----------------------------------------
        // STORE TEST
        //-----------------------------------------

        active_mask = 16'hFFFF;

        for(i=0;i<16;i=i+1) begin
            addr_in[i] = 16'h0100 + i;
            sw_out[i]  = 16'h1000 + i;
        end

        request = 4'b0000;
        warp_id_from_ws = 0;

        @(posedge clk);
        mem_req = 1;

        @(posedge clk);
        mem_req = 0;

        wait(mem_done);

        //-----------------------------------------
        // LOAD TEST
        //-----------------------------------------

        request = 4'b0110;

        @(posedge clk);
        mem_req = 1;

        @(posedge clk);
        mem_req = 0;

        wait(lw_ready);

        for(i=0;i<16;i=i+1) begin
            if(lw_out[i] != (16'h1000+i))
                $fatal(1, "LOAD FAIL lane=%0d",i);
        end

        $display("MEMORY PASS");

        //-----------------------------------------
        // QUEUE TEST
        //-----------------------------------------

        for(i=0;i<4;i=i+1) begin

            warp_id_from_ws = i[1:0];

            @(posedge clk);
            mem_req = 1;

            @(posedge clk);
            mem_req = 0;
        end

        repeat(20) @(posedge clk);

        $display("QUEUE TEST COMPLETE");

        //-----------------------------------------
        // REDIRECT TEST
        //-----------------------------------------

        redirect = 1;
        pc_target = 16'h0200;

        @(posedge clk);

        redirect = 0;

        repeat(3) @(posedge clk);

        $display("Warp PC=%h",warp_ready);

        //-----------------------------------------
        // HALT TEST
        //-----------------------------------------

        repeat(4) begin
            halt = 1;
            @(posedge clk);
            halt = 0;
            repeat(3) @(posedge clk);
        end

        repeat(20) @(posedge clk);

        $display("DONE=%b",done);

        //-----------------------------------------
        // PASS
        //-----------------------------------------

        $display("");
        $display("================================");
        $display("ALL TESTS PASSED");
        $display("================================");
        $display("");

        $finish;

    end
    

endmodule