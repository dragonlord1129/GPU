module reg_file_simt #(
    parameter DATA_WIDTH      = 16,
    parameter NUM_REGS        = 16,
    parameter LANES           = 16,
    parameter NUMBER_OF_WARPS = 4
)(
    input  wire                        clk,
    input  wire                        reset,
    input  wire [3:0]                  rs1_addr,
    input  wire [3:0]                  rs2_addr,
    input  wire [3:0]                  rd_addr,
    input  wire [1:0]                  read_warp_id,
    input  wire [1:0]                  write_warp_id,
    input  wire [LANES-1:0]            active_mask,
    input  wire [DATA_WIDTH-1:0]       write_data [0:LANES-1],
    input  wire                        reg_write,

    // ---- Second write port for load writeback ----
    input  wire [3:0]                  wb2_rd_addr,
    input  wire [1:0]                  wb2_warp_id,
    input  wire [LANES-1:0]            wb2_active_mask,
    input  wire [DATA_WIDTH-1:0]       wb2_write_data [0:LANES-1],
    input  wire                        wb2_reg_write,

    output wire [DATA_WIDTH-1:0]       rs1_data [0:LANES-1],
    output wire [DATA_WIDTH-1:0]       rs2_data [0:LANES-1]
);

    reg [DATA_WIDTH-1:0] REGS [0:NUMBER_OF_WARPS-1][0:LANES-1][0:NUM_REGS-1];

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : READS
            assign rs1_data[i] = (rs1_addr == 0)  ? 0 :
                                 (rs1_addr == 15) ? i[15:0] :
                                 REGS[read_warp_id][i][rs1_addr];
            assign rs2_data[i] = (rs2_addr == 0)  ? 0 :
                                 (rs2_addr == 15) ? i[15:0] :
                                 REGS[read_warp_id][i][rs2_addr];
        end
    endgenerate

    integer w, l;
    always @(posedge clk) begin
        if (reset) begin
            for (w = 0; w < NUMBER_OF_WARPS; w = w + 1)
                for (l = 0; l < LANES; l = l + 1)
                    for (integer r = 0; r < NUM_REGS; r = r + 1)
                        REGS[w][l][r] <= 0;
        end else begin
            // Port 1 – ALU / normal writeback
            if (reg_write) begin
                for (l = 0; l < LANES; l = l + 1) begin
                    if (active_mask[l] && (rd_addr != 0) && (rd_addr != 15))
                        REGS[write_warp_id][l][rd_addr] <= write_data[l];
                end
            end
            // Port 2 – load writeback (independent, simultaneous)
            if (wb2_reg_write) begin
                for (l = 0; l < LANES; l = l + 1) begin
                    if (wb2_active_mask[l] && (wb2_rd_addr != 0) && (wb2_rd_addr != 15))
                        REGS[wb2_warp_id][l][wb2_rd_addr] <= wb2_write_data[l];
                end
            end
        end
    end

endmodule