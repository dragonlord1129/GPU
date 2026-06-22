module tb_reg_file_simt;

reg clk;
reg reset;

reg [3:0] rs1;
reg [3:0] rs2;
reg [3:0] rd;

reg [15:0] active_mask;

reg [15:0] write_data [0:15];

wire [15:0] rs1_data [0:15];
wire [15:0] rs2_data [0:15];

reg_file_simt dut(
    .clk(clk),
    .reset(reset),

    .rs1_addr(rs1),
    .rs2_addr(rs2),
    .rd_addr(rd),

    .active_mask(active_mask),

    .write_data(write_data),

    .reg_write(1'b1),

    .rs1_data(rs1_data),
    .rs2_data(rs2_data)
);

always #5 clk = ~clk;

integer i;

initial begin

    clk = 0;
    reset = 1;

    #20;
    reset = 0;

    rd = 4'd1;
    active_mask = 16'hFFFF;

    for(i=0;i<16;i=i+1)
        write_data[i] = i;

    #10;

    rs1 = 4'd1;

    #1;

    for(i=0;i<16;i=i+1)
        $display("Lane %0d R1=%0d", i, rs1_data[i]);

    $finish;

end

endmodule