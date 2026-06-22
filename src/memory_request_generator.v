module memory_request_generator(
    input MemRead,
    input MemWrite,

    output mem_req,
    output [3:0] request
);

assign mem_req = MemRead | MemWrite;

assign request =
        MemRead  ? 4'b0110 :
        MemWrite ? 4'b0111 :
                   4'b0000;

endmodule