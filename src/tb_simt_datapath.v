`timescale 1ns/1ps

module tb_simt_datapath;

parameter LANES = 16;
parameter DATA_WIDTH = 16;

reg clk;
reg reset;

reg [3:0] rs1_addr;
reg [3:0] rs2_addr;
reg [3:0] rd_addr;

reg [LANES-1:0] active_mask;

reg [3:0] alu_control;

reg reg_write;

wire [DATA_WIDTH-1:0] rs1_data [0:LANES-1];
wire [DATA_WIDTH-1:0] rs2_data [0:LANES-1];

wire [DATA_WIDTH-1:0] alu_result [0:LANES-1];

integer i;

////////////////////////////////////////////////////////////
// REGFILE WRITE DATA
////////////////////////////////////////////////////////////

reg [DATA_WIDTH-1:0] wb_data [0:LANES-1];

////////////////////////////////////////////////////////////
// CLOCK
////////////////////////////////////////////////////////////

always #5 clk = ~clk;

////////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////////

reg_file_simt rf (
    .clk(clk),
    .reset(reset),

    .rs1_addr(rs1_addr),
    .rs2_addr(rs2_addr),
    .rd_addr(rd_addr),

    .active_mask(active_mask),

    .write_data(wb_data),

    .reg_write(reg_write),

    .rs1_data(rs1_data),
    .rs2_data(rs2_data)
);

simt_alu alu (
    .A(rs1_data),
    .B(rs2_data),
    .ALUControl(alu_control),
    .Result(alu_result)
);

////////////////////////////////////////////////////////////
// TEST
////////////////////////////////////////////////////////////

initial begin

    clk = 0;

    reset = 1;
    reg_write = 0;

    rs1_addr = 0;
    rs2_addr = 0;
    rd_addr  = 0;

    active_mask = 16'hFFFF;

    ////////////////////////////////////////////////////////
    // RESET
    ////////////////////////////////////////////////////////

    repeat(2) @(posedge clk);

    reset = 0;

    @(posedge clk);

    ////////////////////////////////////////////////////////
    // WRITE R2 = lane id
    ////////////////////////////////////////////////////////

    for(i=0;i<LANES;i=i+1)
        wb_data[i] = i;

    rd_addr = 4'd2;
    reg_write = 1;

    @(posedge clk);

    #1;
    reg_write = 0;

    $display("RAW CHECK R2");

    for(i=0;i<LANES;i=i+1)
        $display("Lane %0d R2=%0d", i, rf.REGS[i][2]);

    ////////////////////////////////////////////////////////
    // WRITE R3 = 100
    ////////////////////////////////////////////////////////

    for(i=0;i<LANES;i=i+1)
        wb_data[i] = 100;

    rd_addr = 4'd3;
    reg_write = 1;

    @(posedge clk);

    #1;
    reg_write = 0;

    $display("RAW CHECK R3");

    for(i=0;i<LANES;i=i+1)
        $display("Lane %0d R3=%0d", i, rf.REGS[i][3]);

    ////////////////////////////////////////////////////////
    // READ R2,R3
    ////////////////////////////////////////////////////////

    rs1_addr = 4'd2;
    rs2_addr = 4'd3;

    #2;

    ////////////////////////////////////////////////////////
    // ADD
    ////////////////////////////////////////////////////////

    alu_control = 4'b0000;

    #2;

    $display("\nALU RESULTS");

    for(i=0;i<LANES;i=i+1)
        $display("Lane %0d ALU=%0d", i, alu_result[i]);

    ////////////////////////////////////////////////////////
    // WRITE ALU RESULT -> R1
    ////////////////////////////////////////////////////////

    for(i=0;i<LANES;i=i+1)
        wb_data[i] = alu_result[i];

    rd_addr = 4'd1;
    reg_write = 1;

    @(posedge clk);

    #1;
    reg_write = 0;

    ////////////////////////////////////////////////////////
    // RAW CHECK
    ////////////////////////////////////////////////////////

    $display("\nRAW CHECK R1");

    for(i=0;i<LANES;i=i+1)
        $display(
            "Lane %0d R1_RAW=%0d",
            i,
            rf.REGS[i][1]
        );

    ////////////////////////////////////////////////////////
    // READ BACK
    ////////////////////////////////////////////////////////

    rs1_addr = 4'd1;

    #2;

    $display("\n=== SIMT DATAPATH TEST ===");

    for(i=0;i<LANES;i=i+1) begin

        $display(
            "Lane %0d : R1=%0d",
            i,
            rs1_data[i]
        );

        if(rs1_data[i] != (100 + i)) begin

            $display(
                "FAIL lane %0d expected=%0d got=%0d",
                i,
                100+i,
                rs1_data[i]
            );

            $finish;
        end
    end

    $display("");
    $display("========================");
    $display("SIMT DATAPATH PASSED");
    $display("========================");

    $finish;

end

endmodule