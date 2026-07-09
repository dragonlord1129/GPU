module instruction_memory (
    input  [15:0] A,
    output [31:0] RD
);
    reg [31:0] memory [0:32767];
    integer idx;
    initial begin
        // Fill unused entries with HALT
        for (idx = 0; idx < 32768; idx = idx + 1)
            memory[idx] = 32'hA0000000;

        // Warp 0 kernel – Matrix multiplication C = A×B
        // A = 1..16, B = all ones
        memory[0]  = 32'h64F00064;  // LW R4, 100(R15)    ; r = row
        memory[1]  = 32'h65F00074;  // LW R5, 116(R15)    ; c = col
        memory[2]  = 32'h6E0000C8;  // LW R14, 200(R0)    ; R14 = 32
        memory[3]  = 32'h07440000;  // ADD R7, R4, R4     ; R7 = 2r
        memory[4]  = 32'h07770000;  // ADD R7, R7, R7     ; R7 = 4r

        // Load A[r][k]
        memory[5]  = 32'h68700000;  // LW R8,  0(R7)      ; A[r][0]
        memory[6]  = 32'h69700001;  // LW R9,  1(R7)      ; A[r][1]
        memory[7]  = 32'h6A700002;  // LW R10, 2(R7)      ; A[r][2]
        memory[8]  = 32'h6B700003;  // LW R11, 3(R7)      ; A[r][3]

        // Load B[k][c]
        memory[9]  = 32'h61500010;  // LW R1,  16(R5)     ; B[0][c]
        memory[10] = 32'h62500014;  // LW R2,  20(R5)     ; B[1][c]
        memory[11] = 32'h63500018;  // LW R3,  24(R5)     ; B[2][c]
        memory[12] = 32'h6D50001C;  // LW R13, 28(R5)     ; B[3][c]

        // Dot product (temp in R12)
        memory[13] = 32'h5C810000;  // MUL R12, R8, R1    ; A[r][0]*B[0][c]
        memory[14] = 32'h06C00000;  // ADD R6,  R0, R12   ; acc = first product
        memory[15] = 32'h5C920000;  // MUL R12, R9, R2    ; A[r][1]*B[1][c]
        memory[16] = 32'h06C60000;  // ADD R6,  R6, R12
        memory[17] = 32'h5CA30000;  // MUL R12, R10, R3   ; A[r][2]*B[2][c]
        memory[18] = 32'h06C60000;  // ADD R6,  R6, R12
        memory[19] = 32'h5CBD0000;  // MUL R12, R11, R13  ; A[r][3]*B[3][c]
        memory[20] = 32'h06C60000;  // ADD R6,  R6, R12

        // Address = 32 + 4r + c
        memory[21] = 32'h0C750000;  // ADD R12, R7, R5    ; R12 = 4r + c
        memory[22] = 32'h0DCE0000;  // ADD R13, R12, R14  ; R13 = (4r+c) + 32

        // Store result
        memory[23] = 32'h70D60000;  // SW  R6, 0(R13)     ; C[r][c] = acc
        memory[24] = 32'hA0000000;  // HALT
    end
    assign RD = memory[A[14:0]];
endmodule