// tb_gpu_subsystem_full.v

`timescale 1ns/1ps

module tb_gpu_subsystem_full;

parameter LANES = 16;

reg clk;
reg reset;

/////////////////////////////////////////////////////////////
// Decoder inputs
/////////////////////////////////////////////////////////////

reg [31:0] instruction;

wire [3:0] opcode;
wire [3:0] rd;
wire [3:0] rs1;
wire [3:0] rs2;
wire [15:0] imm;

instruction_decoder DEC(
    .instruction(instruction),
    .opcode(opcode),
    .rd(rd),
    .rs1(rs1),
    .rs2(rs2),
    .imm(imm)
);

/////////////////////////////////////////////////////////////
// Control
/////////////////////////////////////////////////////////////

wire RegWrite;
wire MemRead;
wire MemWrite;
wire Branch;
wire Jump;
wire Halt;
wire ALUSrc;

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

wire [3:0] ALUControl;

alu_control ALUCTRL(
    .opcode(opcode),
    .ALUControl(ALUControl)
);

/////////////////////////////////////////////////////////////
// Register File
/////////////////////////////////////////////////////////////

reg [15:0] write_data [0:LANES-1];
reg [15:0] active_mask;

wire [15:0] rs1_data [0:LANES-1];
wire [15:0] rs2_data [0:LANES-1];

reg_file_simt RF(
    .clk(clk),
    .reset(reset),

    .rs1_addr(rs1),
    .rs2_addr(rs2),
    .rd_addr(rd),

    .active_mask(active_mask),

    .write_data(write_data),

    .reg_write(RegWrite),

    .rs1_data(rs1_data),
    .rs2_data(rs2_data)
);

/////////////////////////////////////////////////////////////
// SIMT ALU
/////////////////////////////////////////////////////////////

wire [15:0] alu_result [0:LANES-1];

simt_alu #(
    .LANES(LANES),
    .WIDTH(16)
)
ALU(
    .A(rs1_data),
    .B(rs2_data),
    .ALUControl(ALUControl),
    .Result(alu_result)
);
/////////////////////////////////////////////////////////////
// Memory request generator
/////////////////////////////////////////////////////////////

wire mem_req;
wire [3:0] request;

memory_request_generator REQGEN(
    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .mem_req(mem_req),
    .request(request)
);

/////////////////////////////////////////////////////////////
// Memory scheduler
/////////////////////////////////////////////////////////////

wire stall;
wire mem_done;

wire [15:0] addr_out;

wire mem_write;

wire [15:0] lw_out [0:15];

wire [15:0] lw_line_in [0:15];

wire [15:0] sw_line_out [0:15];

wire [15:0] addr_in [0:15];

wire [15:0] sw_out [0:15];

wire [15:0] sw_mask;

genvar g;

generate
for(g=0; g<16; g=g+1)
begin
    assign addr_in[g] = g;
    assign sw_out[g]  = alu_result[g];
end
endgenerate

memory_scheduler MEMSCHED(
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

    .warp_id_from_ws(2'b00),

    .mem_done(mem_done),
    .warp_id_to_ws(),

    .lw_destination(4'd9),
    .lw_destination_out(),

    .lw_line_in(lw_line_in),

    .addr_out(addr_out),
    .sw_line_out(sw_line_out),
    .sw_word_mask(sw_mask),

    .lw_warp_id(),
    .lw_ready()
);

/////////////////////////////////////////////////////////////
// Data memory
/////////////////////////////////////////////////////////////

data_memory_line DMEM(
    .clk(clk),
    .mem_write(mem_write),

    .addr_base(addr_out),

    .sw_word_mask(sw_mask),
    .sw_line_out(sw_line_out),

    .lw_line_in(lw_line_in)
);

/////////////////////////////////////////////////////////////
// Clock
/////////////////////////////////////////////////////////////

always #5 clk = ~clk;

integer i;

initial begin

    clk = 0;
    reset = 1;
    active_mask = 16'hFFFF;

    #20;
    reset = 0;

    // ===============================
    //  CORRECTED INITIALISATION:
    //  Backdoor writes to the register file
    // ===============================
    for (i = 0; i < 16; i = i + 1) begin
        RF.REGS[i][2] = i;        // R2 = lane index
        RF.REGS[i][3] = 16'd100;  // R3 = 100
    end

    /////////////////////////////////////////////////////////
    // ADD
    /////////////////////////////////////////////////////////

    instruction =
    {
        4'h0,       // ADD opcode
        4'd1,       // rd
        4'd2,       // rs1
        4'd3,       // rs2
        16'd0
    };

    // let decoder/control/RF reads settle
    #1;

    $display("");
    $display("ADD RESULTS");

    for(i=0;i<16;i=i+1)
    begin
        $display(
            "Lane %0d : %0d + %0d = %0d",
            i,
            rs1_data[i],
            rs2_data[i],
            alu_result[i]
        );
    end

    // capture ALU result into write_data
    for(i=0;i<16;i=i+1)
    begin
        write_data[i] = alu_result[i];
    end

    force RF.rd_addr   = 4'd1;
    force RF.reg_write = 1'b1;

    @(posedge clk);

    release RF.rd_addr;
    release RF.reg_write;

    // allow write to complete
    #1;

    $display("");
    $display("VERIFY R1");

    for(i=0;i<16;i=i+1)
    begin
        $display("Lane %0d : R1=%0d", i, RF.REGS[i][1]);

        if(RF.REGS[i][1] !== (i + 100))
        begin
            $display(
                "FAIL lane %0d expected=%0d got=%0d",
                i,
                i+100,
                RF.REGS[i][1]
            );
            $finish;
        end
    end

    /////////////////////////////////////////////////////////
    // STORE
    /////////////////////////////////////////////////////////

    instruction =
    {
        4'h7,
        4'd0,
        4'd1,
        4'd0,
        16'd0
    };

    @(posedge clk);

    repeat(20) @(posedge clk);

    $display("STORE PASS");

    /////////////////////////////////////////////////////////
    // LOAD
    /////////////////////////////////////////////////////////

    instruction =
    {
        4'h6,
        4'd9,
        4'd0,
        4'd0,
        16'd0
    };

    @(posedge clk);

    repeat(20) @(posedge clk);

    $display("LOAD REQUEST PASS");

    /////////////////////////////////////////////////////////
    // DONE
    /////////////////////////////////////////////////////////

    $display("");
    $display("=================================");
    $display("GPU SUBSYSTEM TEST PASSED");
    $display("=================================");
    $display("");

    $finish;

end

endmodule