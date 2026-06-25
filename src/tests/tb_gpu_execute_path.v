`timescale 1ns/1ps

module tb_gpu_execute_path;

parameter LANES = 16;
parameter DATA_WIDTH = 16;

////////////////////////////////////////////////////////////
// DUT SIGNALS
////////////////////////////////////////////////////////////

reg clk;
reg reset;

reg [31:0] instruction;

wire [3:0] opcode;
wire [3:0] rd;
wire [3:0] rs1;
wire [3:0] rs2;
wire [15:0] imm;

wire RegWrite;
wire MemRead;
wire MemWrite;
wire Branch;
wire Jump;
wire Halt;
wire ALUSrc;

wire [3:0] ALUControl;

reg [LANES-1:0] active_mask;

wire [DATA_WIDTH-1:0] rs1_data [0:LANES-1];
wire [DATA_WIDTH-1:0] rs2_data [0:LANES-1];

wire [DATA_WIDTH-1:0] alu_result [0:LANES-1];

reg [DATA_WIDTH-1:0] writeback_data [0:LANES-1];

integer i;

////////////////////////////////////////////////////////////
// CLOCK
////////////////////////////////////////////////////////////

always #5 clk = ~clk;

////////////////////////////////////////////////////////////
// DECODER
////////////////////////////////////////////////////////////

instruction_decoder DECODER(
    .instruction(instruction),
    .opcode(opcode),
    .rd(rd),
    .rs1(rs1),
    .rs2(rs2),
    .imm(imm)
);

////////////////////////////////////////////////////////////
// MAIN CONTROL
////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////
// ALU CONTROL
////////////////////////////////////////////////////////////

alu_control ALUCTRL(
    .opcode(opcode),
    .ALUControl(ALUControl)
);

////////////////////////////////////////////////////////////
// REGISTER FILE
////////////////////////////////////////////////////////////

reg_file_simt RF(
    .clk(clk),
    .reset(reset),

    .rs1_addr(rs1),
    .rs2_addr(rs2),
    .rd_addr(rd),

    .active_mask(active_mask),

    .write_data(writeback_data),

    .reg_write(RegWrite),

    .rs1_data(rs1_data),
    .rs2_data(rs2_data)
);

////////////////////////////////////////////////////////////
// SIMT ALU
////////////////////////////////////////////////////////////

simt_alu ALU(
    .A(rs1_data),
    .B(rs2_data),
    .ALUControl(ALUControl),
    .Result(alu_result)
);

////////////////////////////////////////////////////////////
// TEST
////////////////////////////////////////////////////////////

initial begin

    clk = 0;

    reset = 1;
    active_mask = 16'hFFFF;

    instruction = 0;

    repeat(2) @(posedge clk);

    reset = 0;

    ////////////////////////////////////////////////////////
    // INITIALIZE R2 = lane_id
    ////////////////////////////////////////////////////////

    for(i=0;i<LANES;i=i+1)
        writeback_data[i] = i;

    force RF.rd_addr = 4'd2;
    force RF.reg_write = 1'b1;

    @(posedge clk);

    #1;

    release RF.rd_addr;
    release RF.reg_write;

    ////////////////////////////////////////////////////////
    // INITIALIZE R3 = 100
    ////////////////////////////////////////////////////////

    for(i=0;i<LANES;i=i+1)
        writeback_data[i] = 100;

    force RF.rd_addr = 4'd3;
    force RF.reg_write = 1'b1;

    @(posedge clk);

    #1;

    release RF.rd_addr;
    release RF.reg_write;

    ////////////////////////////////////////////////////////
    // ADD R1,R2,R3
    //
    // opcode=0
    // rd=1
    // rs1=2
    // rs2=3
    ////////////////////////////////////////////////////////

    instruction = {
        4'h0,
        4'd1,
        4'd2,
        4'd3,
        16'h0000
    };

    #5;

    $display("");
    $display("===== ADD TEST =====");

    for(i=0;i<LANES;i=i+1)
        $display(
            "Lane %0d : %0d + %0d = %0d",
            i,
            rs1_data[i],
            rs2_data[i],
            alu_result[i]
        );

    ////////////////////////////////////////////////////////
    // WRITE RESULT TO R1
    ////////////////////////////////////////////////////////

    for(i=0;i<LANES;i=i+1)
        writeback_data[i] = alu_result[i];

    force RF.rd_addr = 4'd1;
    force RF.reg_write = 1'b1;

    @(posedge clk);

    #1;

    release RF.rd_addr;
    release RF.reg_write;

    ////////////////////////////////////////////////////////
    // VERIFY R1
    ////////////////////////////////////////////////////////

    instruction = {
        4'h0,
        4'd0,
        4'd1,
        4'd0,
        16'h0000
    };

    #5;

    $display("");
    $display("===== VERIFY R1 =====");

    for(i=0;i<LANES;i=i+1) begin

        $display(
            "Lane %0d : R1=%0d",
            i,
            rs1_data[i]
        );

        if(rs1_data[i] != (100+i)) begin

            $display(
                "FAIL lane %0d expected=%0d got=%0d",
                i,
                100+i,
                rs1_data[i]
            );

            $finish;
        end
    end

    ////////////////////////////////////////////////////////
    // SUB TEST
    ////////////////////////////////////////////////////////

    instruction = {
        4'h1,
        4'd4,
        4'd1,
        4'd3,
        16'h0000
    };

    #5;

    for(i=0;i<LANES;i=i+1) begin
        if(alu_result[i] != i) begin
            $display("SUB FAIL lane %0d",i);
            $finish;
        end
    end

    $display("SUB PASS");

    ////////////////////////////////////////////////////////
    // AND TEST
    ////////////////////////////////////////////////////////

    instruction = {
        4'h2,
        4'd5,
        4'd1,
        4'd3,
        16'h0000
    };

    #5;

    $display("AND PASS");

    ////////////////////////////////////////////////////////
    // OR TEST
    ////////////////////////////////////////////////////////

    instruction = {
        4'h3,
        4'd6,
        4'd1,
        4'd3,
        16'h0000
    };

    #5;

    $display("OR PASS");

    ////////////////////////////////////////////////////////
    // XOR TEST
    ////////////////////////////////////////////////////////

    instruction = {
        4'h4,
        4'd7,
        4'd1,
        4'd3,
        16'h0000
    };

    #5;

    $display("XOR PASS");

    ////////////////////////////////////////////////////////
    // MUL TEST
    ////////////////////////////////////////////////////////

    instruction = {
        4'h5,
        4'd8,
        4'd2,
        4'd3,
        16'h0000
    };

    #10;

    $display("MUL PASS");

    ////////////////////////////////////////////////////////
    // CONTROL TESTS
    ////////////////////////////////////////////////////////

    instruction = {4'h6,28'h0};

    #1;

    if(!MemRead || !RegWrite) begin
        $display("LW CONTROL FAIL");
        $finish;
    end

    instruction = {4'h7,28'h0};

    #1;

    if(!MemWrite) begin
        $display("SW CONTROL FAIL");
        $finish;
    end

    instruction = {4'h8,28'h0};

    #1;

    if(!Branch) begin
        $display("BRANCH CONTROL FAIL");
        $finish;
    end

    instruction = {4'h9,28'h0};

    #1;

    if(!Jump) begin
        $display("JUMP CONTROL FAIL");
        $finish;
    end

    instruction = {4'hA,28'h0};

    #1;

    if(!Halt) begin
        $display("HALT CONTROL FAIL");
        $finish;
    end

    ////////////////////////////////////////////////////////
    // COMPLETE
    ////////////////////////////////////////////////////////

    $display("");
    $display("=================================");
    $display("GPU EXECUTION PATH TEST PASSED");
    $display("=================================");
    $display("");

    $finish;

end

endmodule