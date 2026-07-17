module neural_network_digits #(
    // Parameters
        parameter int IMAGE_PIXEL_WIDTH     = 4,
        parameter int IMAGE_HORIZONTAL_SIZE = 8,
        parameter int IMAGE_VERTICAL_SIZE   = 8,
        parameter int DIGIT_WIDTH           = 5
)(
    // Inputs
        input  logic clk,
        input  logic rst,
        input  logic start,
        input  logic [IMAGE_PIXEL_WIDTH-1:0] image [IMAGE_HORIZONTAL_SIZE-1:0][IMAGE_VERTICAL_SIZE-1:0],

    // Outputs
        output logic done,
        output logic [DIGIT_WIDTH-1:0] digit
);

    // Constantes PDF
        localparam int N_IN    = 64;   // pixeles de entrada
        localparam int N_HID   = 16;   // neuronas capa oculta
        localparam int N_OUT   = 10;   // neuronas capa de salida (digitos)
        localparam int SHIFT1  = 5;    // requantizacion de la capa oculta

    // Memorias
        logic signed [7:0]  weight_rom  [0:1183];
        logic signed [31:0] bias_rom    [0:25];
        
    // Neuronas calculadas
        logic        [7:0]  n_oculta    [0:N_HID-1];

    // Lectura de data
        initial begin
            $readmemh("weights.hex", weight_rom);
            $readmemh("biases.hex",  bias_rom);
        end

    // Variables
        logic signed [31:0]     max, sum;
        logic signed [15:0]     prod;
        logic [10:0]            w_addr;
        logic [7:0]             n_select;
        logic [6:0]             last_i_i;
        logic [6:0]             i_i;
        logic [4:0]             b_addr;
        logic [3:0]             i_n;
        logic [2:0]             x, y;
        logic [3:0]             i_m;
        logic [3:0]             last_i_n;
        logic                   layer;

    // Ultimos indices de comparación para iterar
        assign last_i_i = layer ? (N_HID-1) : (N_IN-1);
        assign last_i_n = layer ? (N_OUT-1) : (N_HID-1);

    // Calculo de la direccion de bias y peso de la neurona actual con offset por Layer 1 o 2
        assign b_addr = layer ? (5'd16 + i_n)              : i_n;
        assign w_addr = layer ? (11'd1024 + i_n*16 + i_i)  : (i_n*64 + i_i);

    // Valores de 0..7 en x/y (fila/columna dentro de la imagen 8x8)
        assign x = i_i[2:0];   // columna
        assign y = i_i[5:3];   // fila

    // Seleccionar entre imagen o neurona oculta para los productos
        assign n_select = layer ? n_oculta[i_i[3:0]] : {4'b0, image[y][x]};

    // Producto en funcion de indices y neuronas xd
        //assign prod = weight_rom[w_addr] * $signed({1'b0, n_select});

    // FMA
logic signed [31:0] fma_;

fma_3 #(
    .SRC1_WIDTH(8),
    .SRC2_WIDTH(9),
    .SRC3_WIDTH(32)
) fmaxd (
    .srca(weight_rom[w_addr]),
    .srcb($signed({1'b0,n_select})),
    .srcc(sum),
    .is_fma(1'b1),
    .is_signed(1'b1),
    .result(fma_)
);

    // Estados FSM
        localparam [2:0] IDDLE = 3'h0;
        localparam [2:0] BIAS  = 3'h1;
        localparam [2:0] L1    = 3'h2;
        localparam [2:0] L2    = 3'h3;
        localparam [2:0] DONE  = 3'h4;

        logic       [2:0]   state;


    always_ff @(posedge clk) begin
        if (rst) begin
            state    <= IDDLE;
            i_n      <= '0;
            i_i      <= '0;
            done     <= 1'b0;
            digit    <= '0;
            sum      <= '0;
            layer    <= 1'b0;
            max      <= '0;
            i_m <= '0;
        end

        else begin
            case (state)
                IDDLE: begin
                    done  <= 1'b0;
                    if (start) begin
                        layer <= 1'b0;
                        i_n   <= '0;
                        max   <= 32'h8000_0000; // Mas negativo
                        state <= BIAS;
                    end
                end

                BIAS: begin
                    sum <= bias_rom[b_addr];
                    i_i <= '0;
                    state <= L1;
                end

                // Calculo de neuronas
                L1: begin
                    sum <= fma_;
                    if (i_i >= last_i_i) begin
                        state <= L2;
                    end
                    else begin
                        i_i <= i_i + 1'b1;
                    end
                end

                L2: begin
                    if (!layer) begin
                        logic signed [31:0] relu;
                        logic [7:0]         sat;

                        relu    = sum[31] ? 32'sd0 : sum;                                           // ReLU
                        sat     = ({{5{relu[31]}}, relu[31:5]} > 32'sd255) ? 8'hFF : relu[12:5];    // Sat
                        n_oculta[i_n] <= sat;                                                       // Guardamos el dato xd    
                                        
                        if (i_n >= last_i_n) begin
                            layer <= 1'b1;
                            i_n   <= '0;
                        end
                        else begin
                            i_n <= i_n + 1'b1;
                        end

                        state <= BIAS;
                    end

                    else begin
                        if (sum > max) begin
                            max <= sum;         // Salvar nuevo maximo valor
                            i_m <= i_n;         // Salvar index de ese valor xd
                        end

                        if (i_n == last_i_n) begin
                            state <= DONE;
                        end
                        else begin
                            i_n   <= i_n + 1'b1;
                            state <= BIAS;
                        end
                    end
                end

                DONE: begin
                    done  <= 1'b1;
                    digit <= {1'b0, i_m};
                    state <= IDDLE;
                end

                default:
                    state <= IDDLE;
            endcase
        end
    end

    endmodule