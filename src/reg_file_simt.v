module reg_file_simt #(
    parameter DATA_WIDTH = 16,
    parameter NUM_REGS   = 16,
    parameter LANES      = 16
)(
    input clk,
    input reset,

    input [3:0] rs1_addr,
    input [3:0] rs2_addr,
    input [3:0] rd_addr,

    input [LANES-1:0] active_mask,

    input [DATA_WIDTH-1:0] write_data [0:LANES-1],

    input reg_write,

    output [DATA_WIDTH-1:0] rs1_data [0:LANES-1],
    output [DATA_WIDTH-1:0] rs2_data [0:LANES-1]
);

    reg [DATA_WIDTH-1:0] REGS [0:LANES-1][0:NUM_REGS-1];

    integer lane;
    integer regid;

    //////////////////////////////////////////////////////
    // Reads
    //////////////////////////////////////////////////////

    genvar i;

    generate
        for(i=0;i<LANES;i=i+1) begin : READS

            assign rs1_data[i] =
                (rs1_addr == 0) ?
                0 :
                REGS[i][rs1_addr];

            assign rs2_data[i] =
                (rs2_addr == 0) ?
                0 :
                REGS[i][rs2_addr];

        end
    endgenerate

    //////////////////////////////////////////////////////
    // Writes
    //////////////////////////////////////////////////////

    always @(posedge clk) begin

        if(reset) begin

            for(lane=0; lane<LANES; lane=lane+1)
                for(regid=0; regid<NUM_REGS; regid=regid+1)
                    REGS[lane][regid] <= 0;

        end
        else begin

            if(reg_write) begin

                for(lane=0; lane<LANES; lane=lane+1) begin

                    if(active_mask[lane]) begin

                        if(rd_addr != 0)
                            REGS[lane][rd_addr]
                                <= write_data[lane];

                    end

                end

            end

        end

    end

endmodule