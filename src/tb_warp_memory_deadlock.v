`timescale 1ns/1ps

module tb_warp_memory_deadlock;

reg clk;
reg reset;

// ========================================================
// Warp Scheduler Interface
// ========================================================

reg         mem_req;
reg         mem_done;
reg  [1:0]  warp_id_from_ms;

reg         halt;
reg         hold;
reg         redirect;
reg [15:0]  pc_target;

wire [1:0]  warp_id_to_ms;
wire [1:0]  current_warp_id;
wire [1:0] warp_id_from_ms_ms;
wire [15:0] warp_ready;
wire [15:0] warp_ready_mask;
wire        running;
wire        done;

// ========================================================
// Memory Scheduler Interface
// ========================================================

reg  [3:0] request;

reg [15:0] addr_in [0:15];
reg [15:0] sw_out  [0:15];

wire [15:0] lw_out [0:15];

wire stall;
wire mem_write;

wire [15:0] addr_out;

wire [15:0] sw_line_out [0:15];
wire [15:0] lw_line_in  [0:15];

wire [15:0] sw_word_mask;

wire [1:0] lw_warp_id;
wire       lw_ready;

reg [3:0] lw_destination;
wire [3:0] lw_destination_out;

// ========================================================
// DUTs
// ========================================================

warp_scheduler ws (
    .clk(clk),
    .rst(reset),

    .mem_req(mem_req),
    .mem_done(mem_done),

    .warp_id_from_ms(warp_id_from_ms),

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

memory_scheduler ms (
    .clk(clk),
    .reset(reset),

    .request(request),
    .active_mask(16'hFFFF),

    .addr_in(addr_in),
    .sw_out(sw_out),

    .lw_out(lw_out),

    .stall(stall),
    .mem_write(mem_write),

    .mem_req(mem_req),

    .warp_id_from_ws(warp_id_to_ms),

    .mem_done(mem_done_ms),
    .warp_id_to_ws(warp_id_from_ms_ms),

    .lw_destination(lw_destination),
    .lw_destination_out(lw_destination_out),

    .lw_line_in(lw_line_in),

    .addr_out(addr_out),
    .sw_line_out(sw_line_out),
    .sw_word_mask(sw_word_mask),

    .lw_warp_id(lw_warp_id),
    .lw_ready(lw_ready)
);

data_memory_line dmem (
    .clk(clk),

    .mem_write(mem_write),

    .addr_base(addr_out),

    .sw_word_mask(sw_word_mask),

    .sw_line_out(sw_line_out),

    .lw_line_in(lw_line_in)
);

// ========================================================
// Manual connection
// ========================================================

assign mem_done_ms_wire = mem_done_ms;

always @(*) begin
    mem_done        = mem_done_ms;
    warp_id_from_ms = warp_id_from_ms_ms;
end

// ========================================================
// Clock
// ========================================================

always #5 clk = ~clk;

// ========================================================
// Helpers
// ========================================================

integer i;

task issue_load;
begin

    request = 4'b0110; // LW

    for(i=0;i<16;i=i+1)
        addr_in[i] = i;

    mem_req = 1'b1;

    @(posedge clk);

    mem_req = 1'b0;

end
endtask

// ========================================================
// Test
// ========================================================

initial begin

    clk = 0;
    reset = 1;

    mem_req = 0;
    mem_done = 0;
    warp_id_from_ms = 0;

    halt = 0;
    hold = 0;
    redirect = 0;
    pc_target = 0;

    request = 4'b0110;
    lw_destination = 4'd1;

    for(i=0;i<16;i=i+1) begin
        addr_in[i] = i;
        sw_out[i]  = 16'h1000 + i;
    end

    repeat(3) @(posedge clk);

    reset = 0;

    //----------------------------------------------------
    // Request #1
    //----------------------------------------------------

    $display("\n--- ISSUE LOAD FOR WARP0 ---");

    issue_load();

    //----------------------------------------------------
    // Wait until memory scheduler enters WAIT/CAPTURE
    //----------------------------------------------------

    repeat(2) @(posedge clk);

    //----------------------------------------------------
    // BUG TRIGGER
    //----------------------------------------------------
    // Scheduler cannot accept request now.
    // Warp scheduler WILL stall warp.
    //----------------------------------------------------

    $display("\n--- ISSUE LOAD DURING WAIT/CAPTURE ---");

    issue_load();

    //----------------------------------------------------
    // Observe
    //----------------------------------------------------

    repeat(40) @(posedge clk);

    $display("\n=================================================");
    $display("Current Warp       = %0d", current_warp_id);
    $display("Warp0 Stall        = %0d", ws.WARP_STALL[0]);
    $display("Warp1 Stall        = %0d", ws.WARP_STALL[1]);
    $display("Warp2 Stall        = %0d", ws.WARP_STALL[2]);
    $display("Warp3 Stall        = %0d", ws.WARP_STALL[3]);

    $display("Memory State       = %0d", ms.state_curr);

    $display("REQ_DONE[0]        = %0d", ms.REQ_DONE[0]);
    $display("REQ_DONE[1]        = %0d", ms.REQ_DONE[1]);

    $display("=================================================\n");

    //----------------------------------------------------
    // Failure Detection
    //----------------------------------------------------

    if(ws.WARP_STALL[0] &&
       !mem_done_ms &&
       current_warp_id != 0)
    begin
        $display("DEADLOCK DETECTED");
        $display("Memory request lost");
        $display("Warp remains stalled forever");
    end
    else begin
        $display("TEST FAILED TO REPRODUCE BUG");
    end

    $finish;
end

endmodule