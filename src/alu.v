// ============================================================
// ALU MODULE
// ============================================================

module alu #(
    parameter WIDTH     = 32,
    parameter ALU_WIDTH = 4
)(
    input  [WIDTH-1:0]     A,
    input  [WIDTH-1:0]     B,
    input  [ALU_WIDTH-1:0] ALUControl,

    output [WIDTH-1:0]     result,
    output                 carry,
    output                 zero,
    output                 overflow,
    output                 negative,
    output                 divide_by_zero
);

    // ========================================================
    // ADD / SUB
    // ========================================================

    wire [WIDTH-1:0] B_mux;
    wire [WIDTH-1:0] sum;
    wire             cout;

    assign B_mux       = ALUControl[0] ? ~B : B;
    assign {cout, sum} = A + B_mux + ALUControl[0];

    // ========================================================
    // SLT
    // ========================================================

    wire slt_bit;

    assign slt_bit = sum[WIDTH-1] ^ overflow;

    wire [WIDTH-1:0] slt_result;

    assign slt_result = {{WIDTH-1{1'b0}}, slt_bit};

    // ========================================================
    // MULTIPLIER
    // ========================================================

    wire [2*WIDTH-1:0] mul_full;

    booth_multiplier #(
        .N(WIDTH)
    ) u_mul (
        .multiplicand(A),
        .multiplier(B),
        .product(mul_full)
    );

    wire [WIDTH-1:0] mul_result_low;
    wire [WIDTH-1:0] mul_result_high;

    assign mul_result_low  = mul_full[WIDTH-1:0];
    assign mul_result_high = mul_full[2*WIDTH-1:WIDTH];

    // ========================================================
    // DIVIDER
    // ========================================================

    wire [WIDTH-1:0] div_quotient;
    wire [WIDTH-1:0] div_remainder;

    non_restoring_divider_comb #(
        .WIDTH(WIDTH)
    ) u_div (
        .dividend(A),
        .divisor(B),
        .signed_mode(1'b1),
        .quotient(div_quotient),
        .remainder(div_remainder),
        .divide_by_zero(divide_by_zero)
    );

    // ========================================================
    // RESULT MUX
    // ========================================================

    reg [WIDTH-1:0] mux_out;

    always @(*) begin
        case (ALUControl)

            4'b0000: mux_out = sum;              // ADD
            4'b0001: mux_out = sum;              // SUB

            4'b0010: mux_out = A & B;            // AND
            4'b0011: mux_out = A | B;            // OR
            4'b0100: mux_out = A ^ B;            // XOR

            4'b0101: mux_out = mul_result_low;   // MUL LOW
            4'b0110: mux_out = mul_result_high;  // MUL HIGH

            4'b0111: mux_out = div_quotient;     // DIV
            4'b1000: mux_out = div_remainder;    // REM

            4'b1001: mux_out = slt_result;       // SLT

            default: mux_out = {WIDTH{1'b0}};

        endcase
    end

    assign result = mux_out;

    // ========================================================
    // FLAGS
    // ========================================================

    assign zero     = ~|result;
    assign carry    = cout & ~ALUControl[1];
    assign negative = result[WIDTH-1];

    assign overflow =
        ~ALUControl[2] &
        ~ALUControl[1] &
        (sum[WIDTH-1] ^ A[WIDTH-1]) &
        ~(ALUControl[0] ^ A[WIDTH-1] ^ B[WIDTH-1]);

endmodule


// ============================================================
// BOOTH MULTIPLIER (CORRECTED)
// ============================================================

module booth_multiplier #(
    parameter N = 32
)(
    input  signed [N-1:0]       multiplicand,
    input  signed [N-1:0]       multiplier,
    output reg signed [2*N-1:0] product
);

    integer i;

    reg signed [N:0]   A;      // N+1 bits (sign-extended accumulator)
    reg        [N-1:0] Q;      // N bits   (running multiplier)
    reg signed [N-1:0] M;      // N bits   (multiplicand)
    reg                Q_1;    // 1 bit    (previous LSB of Q)

    reg signed [2*N+1:0] temp; // 2N+2 bits for {A(N+1), Q(N), Q_1(1)}

    always @(*) begin
        A   = {{1{multiplicand[N-1]}}, {N{1'b0}}};  // sign-extended zero
        Q   = multiplier;
        M   = multiplicand;
        Q_1 = 1'b0;

        for (i = 0; i < N; i = i + 1) begin

            // Step 1: add/subtract based on {Q[0], Q_1}
            case ({Q[0], Q_1})
                2'b01: A = A + {{1{M[N-1]}}, M};   // sign-extend M to N+1 bits
                2'b10: A = A - {{1{M[N-1]}}, M};
                default: ;
            endcase

            // Step 2: arithmetic right shift of {A, Q, Q_1} as one unit
            // Total width = (N+1) + N + 1 = 2N+2
            temp = $signed({A, Q, Q_1}) >>> 1;

            //  temp[2N+1:N+1] = new A  (N+1 bits)
            //  temp[N:1]      = new Q  (N bits)
            //  temp[0]        = new Q_1 (1 bit)
            A   = temp[2*N+1 : N+1];
            Q   = temp[N     : 1  ];
            Q_1 = temp[0];

        end

        product = {A[N-1:0], Q};  // drop the extra sign bit of A
    end

endmodule


// ============================================================
// NON-RESTORING DIVIDER
// ============================================================

module non_restoring_divider_comb #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] dividend,
    input  wire [WIDTH-1:0] divisor,
    input  wire             signed_mode,

    output reg  [WIDTH-1:0] quotient,
    output reg  [WIDTH-1:0] remainder,
    output reg              divide_by_zero
);

    integer i;

    reg [WIDTH:0]   A;
    reg [WIDTH-1:0] Q;
    reg [WIDTH-1:0] M;

    reg [WIDTH-1:0] dividend_abs;
    reg [WIDTH-1:0] divisor_abs;

    reg dividend_sign;
    reg divisor_sign;

    reg quotient_sign;
    reg remainder_sign;

    reg [WIDTH:0] tempA;

    always @(*) begin

        quotient       = 0;
        remainder      = 0;
        divide_by_zero = 0;

        if (divisor == 0) begin

            divide_by_zero = 1'b1;

        end
        else begin

            dividend_sign = signed_mode & dividend[WIDTH-1];
            divisor_sign  = signed_mode & divisor[WIDTH-1];

            dividend_abs =
                dividend_sign ? (~dividend + 1'b1) : dividend;

            divisor_abs =
                divisor_sign ? (~divisor + 1'b1) : divisor;

            quotient_sign  = dividend_sign ^ divisor_sign;
            remainder_sign = dividend_sign;

            A = 0;
            Q = dividend_abs;
            M = divisor_abs;

            for (i = 0; i < WIDTH; i = i + 1) begin

                A = {A[WIDTH-1:0], Q[WIDTH-1]};
                Q = {Q[WIDTH-2:0], 1'b0};

                if (A[WIDTH] == 0)
                    tempA = A - {1'b0, M};
                else
                    tempA = A + {1'b0, M};

                Q[0] = (tempA[WIDTH] == 0);

                A = tempA;

            end

            // Final correction
            if (A[WIDTH] == 1)
                A = A + {1'b0, M};

            quotient =
                quotient_sign ? (~Q + 1'b1) : Q;

            remainder =
                remainder_sign ? (~A[WIDTH-1:0] + 1'b1)
                               : A[WIDTH-1:0];

        end
    end

endmodule