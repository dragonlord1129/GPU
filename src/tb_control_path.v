`timescale 1ns/1ps

module tb_control_path;

reg [3:0] opcode;

wire RegWrite;
wire MemRead;
wire MemWrite;
wire Branch;
wire Jump;
wire Halt;
wire ALUSrc;

wire [3:0] ALUControl;

wire mem_req;
wire [3:0] request;

reg [15:0] alu_result;
reg [15:0] mem_result;
wire [15:0] wb_data;

reg lw_ready;
reg [15:0] load_data;
reg [3:0] destination_reg;

wire load_reg_write;
wire [3:0] load_rd;
wire [15:0] load_wb_data;

main_control MC(
    .opcode(opcode),
    .RegWrite(RegWrite),
    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .Branch(Branch),
    .Jump(Jump),
    .Halt(Halt),
    .ALUSrc(ALUSrc)
);

alu_control AC(
    .opcode(opcode),
    .ALUControl(ALUControl)
);

memory_request_generator MRG(
    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .mem_req(mem_req),
    .request(request)
);

writeback_mux WBM(
    .alu_result(alu_result),
    .mem_result(mem_result),
    .MemRead(MemRead),
    .wb_data(wb_data)
);

load_return_unit LRU(
    .lw_ready(lw_ready),
    .load_data(load_data),
    .destination_reg(destination_reg),
    .reg_write(load_reg_write),
    .rd(load_rd),
    .wb_data(load_wb_data)
);

initial begin

    //--------------------------------
    // ADD
    //--------------------------------

    opcode = 4'h0;
    #1;

    if(!RegWrite) begin
        $display("FAIL ADD decode");
        $finish;
    end

    if(ALUControl != 4'b0000) begin
        $display("FAIL ADD alu");
        $finish;
    end

    //--------------------------------
    // MUL
    //--------------------------------

    opcode = 4'h5;
    #1;

    if(ALUControl != 4'b0101) begin
        $display("FAIL MUL");
        $finish;
    end

    //--------------------------------
    // LW
    //--------------------------------

    opcode = 4'h6;
    #1;

    if(!MemRead) begin
        $display("FAIL LW decode");
        $finish;
    end

    if(!mem_req) begin
        $display("FAIL LW mem_req");
        $finish;
    end

    if(request != 4'b0110) begin
        $display("FAIL LW request");
        $finish;
    end

    //--------------------------------
    // SW
    //--------------------------------

    opcode = 4'h7;
    #1;

    if(!MemWrite) begin
        $display("FAIL SW decode");
        $finish;
    end

    if(request != 4'b0111) begin
        $display("FAIL SW request");
        $finish;
    end

    //--------------------------------
    // BRANCH
    //--------------------------------

    opcode = 4'h8;
    #1;

    if(!Branch) begin
        $display("FAIL BRANCH");
        $finish;
    end

    //--------------------------------
    // JUMP
    //--------------------------------

    opcode = 4'h9;
    #1;

    if(!Jump) begin
        $display("FAIL JUMP");
        $finish;
    end

    //--------------------------------
    // HALT
    //--------------------------------

    opcode = 4'hA;
    #1;

    if(!Halt) begin
        $display("FAIL HALT");
        $finish;
    end

    //--------------------------------
    // WB mux ALU
    //--------------------------------

    opcode = 4'h0;

    alu_result = 16'h1234;
    mem_result = 16'hABCD;

    #1;

    if(wb_data != 16'h1234) begin
        $display("FAIL WB ALU");
        $finish;
    end

    //--------------------------------
    // WB mux LOAD
    //--------------------------------

    opcode = 4'h6;

    alu_result = 16'h1234;
    mem_result = 16'hABCD;

    #1;

    if(wb_data != 16'hABCD) begin
        $display("FAIL WB LOAD");
        $finish;
    end

    //--------------------------------
    // LOAD RETURN UNIT
    //--------------------------------

    lw_ready = 1;

    load_data = 16'h5555;
    destination_reg = 4'd7;

    #1;

    if(!load_reg_write) begin
        $display("FAIL LOAD WB enable");
        $finish;
    end

    if(load_rd != 4'd7) begin
        $display("FAIL LOAD WB rd");
        $finish;
    end

    if(load_wb_data != 16'h5555) begin
        $display("FAIL LOAD WB data");
        $finish;
    end

    $display("");
    $display("===============================");
    $display("CONTROL PATH TEST PASSED");
    $display("===============================");
    $display("");

    $finish;

end

endmodule