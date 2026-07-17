module fma_3#(
    // Parameters
        parameter  int SRC1_WIDTH   = 64,
        parameter  int SRC2_WIDTH   = SRC1_WIDTH,
        parameter  int SRC3_WIDTH   = SRC1_WIDTH
    )(
    // Inputs
        input  logic [SRC1_WIDTH-1:0]   srca,
        input  logic [SRC2_WIDTH-1:0]   srcb,
        input  logic [SRC3_WIDTH-1:0]   srcc,
        input  logic                    is_fma,
        input  logic                    is_signed,
        
    // Outputs
        output logic [RESULT_WIDTH-1:0] result
);

        localparam int RESULT_WIDTH = ((SRC1_WIDTH + SRC2_WIDTH) > SRC3_WIDTH) ? (SRC1_WIDTH + SRC2_WIDTH) : SRC3_WIDTH;
    localparam int N_PP       = SRC2_WIDTH;
    localparam int MAX_ROWS   = 2 * N_PP;
    localparam int MAX_STAGES = N_PP;

    logic [RESULT_WIDTH-1:0] a_ext;
    logic [RESULT_WIDTH-1:0] pp [0:N_PP-1];

    logic [RESULT_WIDTH-1:0] stage      [0:MAX_STAGES][0:MAX_ROWS-1];
    logic [RESULT_WIDTH-1:0] next_stage [0:MAX_ROWS-1];

    logic [RESULT_WIDTH-1:0] sum_;
    logic [RESULT_WIDTH-1:0] carry_;
    logic [RESULT_WIDTH-1:0] final_a, final_b;

    logic [RESULT_WIDTH-1:0] mult_result;
    logic [RESULT_WIDTH-1:0] srcc_ext;

    integer i, s, rows, groups, rem, next_rows;

    // Extensión base de A para unsigned path
    assign a_ext = {{(RESULT_WIDTH-SRC1_WIDTH){is_signed & srca[SRC1_WIDTH-1]}}, srca};

    // Productos parciales unsigned/directos
    generate
        genvar g;
        for (g = 0; g < N_PP; g++) begin : GEN_PP
            assign pp[g] = srcb[g] ? (a_ext << g) : '0;
        end
    endgenerate

    always_comb begin
        // inicialización
        for (s = 0; s <= MAX_STAGES; s = s + 1) begin
            for (i = 0; i < MAX_ROWS; i = i + 1) begin
                stage[s][i] = '0;
            end
        end

        for (i = 0; i < MAX_ROWS; i = i + 1) begin
            next_stage[i] = '0;
        end

        sum_        = '0;
        carry_      = '0;
        final_a     = '0;
        final_b     = '0;
        mult_result = '0;
        srcc_ext    = '0;

        if (!is_signed) begin
            // ==================================
            // UNSIGNED MULTIPLICATION
            // ==================================
            for (i = 0; i < N_PP; i = i + 1) begin
                stage[0][i] = pp[i];
            end

            rows = N_PP;
            s    = 0;

            while (rows > 2) begin
                groups    = rows / 3;
                rem       = rows % 3;
                next_rows = 0;

                for (i = 0; i < MAX_ROWS; i = i + 1) begin
                    next_stage[i] = '0;
                end

                for (i = 0; i < groups; i = i + 1) begin
                    sum_   = stage[s][3*i] ^ stage[s][3*i+1] ^ stage[s][3*i+2];
                    carry_ = ((stage[s][3*i]   & stage[s][3*i+1]) |
                              (stage[s][3*i]   & stage[s][3*i+2]) |
                              (stage[s][3*i+1] & stage[s][3*i+2])) << 1;

                    next_stage[next_rows]     = sum_;
                    next_stage[next_rows + 1] = carry_;
                    next_rows = next_rows + 2;
                end

                if (rem == 1) begin
                    next_stage[next_rows] = stage[s][rows-1];
                    next_rows = next_rows + 1;
                end
                else if (rem == 2) begin
                    next_stage[next_rows]     = stage[s][rows-2];
                    next_stage[next_rows + 1] = stage[s][rows-1];
                    next_rows = next_rows + 2;
                end

                for (i = 0; i < next_rows; i = i + 1) begin
                    stage[s+1][i] = next_stage[i];
                end

                rows = next_rows;
                s    = s + 1;
            end

            final_a = stage[s][0];
            if (rows == 2)
                final_b = stage[s][1];
            else
                final_b = '0;

            mult_result = final_a + final_b;
            srcc_ext    = {{(RESULT_WIDTH-SRC3_WIDTH){1'b0}}, srcc};

            if (is_fma)
                result = mult_result + srcc_ext;
            else
                result = mult_result;
        end
        else begin
            // ==================================
            // SIGNED MULTIPLICATION
            // ==================================
            logic sign_res;
            logic [SRC1_WIDTH-1:0] a_mag_small;
            logic [SRC2_WIDTH-1:0] b_mag_small;
            logic [RESULT_WIDTH-1:0] a_mag_ext;
            logic [RESULT_WIDTH-1:0] pp_signed [0:N_PP-1];
            logic [RESULT_WIDTH-1:0] mag_result;
            logic [RESULT_WIDTH-1:0] mult_signed_result;
            logic [RESULT_WIDTH-1:0] srcc_signed_ext;

            sign_res = srca[SRC1_WIDTH-1] ^ srcb[SRC2_WIDTH-1];

            a_mag_small = srca[SRC1_WIDTH-1] ? (~srca + 1'b1) : srca;
            b_mag_small = srcb[SRC2_WIDTH-1] ? (~srcb + 1'b1) : srcb;

            a_mag_ext = {{(RESULT_WIDTH-SRC1_WIDTH){1'b0}}, a_mag_small};

            for (i = 0; i < N_PP; i = i + 1) begin
                pp_signed[i] = b_mag_small[i] ? (a_mag_ext << i) : '0;
                stage[0][i]  = pp_signed[i];
            end

            rows = N_PP;
            s    = 0;

            while (rows > 2) begin
                groups    = rows / 3;
                rem       = rows % 3;
                next_rows = 0;

                for (i = 0; i < MAX_ROWS; i = i + 1) begin
                    next_stage[i] = '0;
                end

                for (i = 0; i < groups; i = i + 1) begin
                    sum_   = stage[s][3*i] ^ stage[s][3*i+1] ^ stage[s][3*i+2];
                    carry_ = ((stage[s][3*i]   & stage[s][3*i+1]) |
                              (stage[s][3*i]   & stage[s][3*i+2]) |
                              (stage[s][3*i+1] & stage[s][3*i+2])) << 1;

                    next_stage[next_rows]     = sum_;
                    next_stage[next_rows + 1] = carry_;
                    next_rows = next_rows + 2;
                end

                if (rem == 1) begin
                    next_stage[next_rows] = stage[s][rows-1];
                    next_rows = next_rows + 1;
                end
                else if (rem == 2) begin
                    next_stage[next_rows]     = stage[s][rows-2];
                    next_stage[next_rows + 1] = stage[s][rows-1];
                    next_rows = next_rows + 2;
                end

                for (i = 0; i < next_rows; i = i + 1) begin
                    stage[s+1][i] = next_stage[i];
                end

                rows = next_rows;
                s    = s + 1;
            end

            mag_result = stage[s][0] + ((rows == 2) ? stage[s][1] : '0);

            if (sign_res)
                mult_signed_result = ~mag_result + 1'b1;
            else
                mult_signed_result = mag_result;

            srcc_signed_ext = {{(RESULT_WIDTH-SRC3_WIDTH){srcc[SRC3_WIDTH-1]}}, srcc};

            if (is_fma)
                result = mult_signed_result + srcc_signed_ext;
            else
                result = mult_signed_result;
        end
    end

endmodule