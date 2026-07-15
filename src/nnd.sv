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

  // Parametros
    localparam int N_IN    = 64;   // pixeles de entrada
    localparam int N_HID   = 16;   // neuronas capa oculta
    localparam int N_OUT   = 10;   // neuronas capa de salida (digitos)
    localparam int SHIFT1  = 5;    // requantizacion de la capa oculta

  // --------------------------------------------------------------------
  // Memorias: ROM de pesos (1184 x int8) y ROM de biases (26 x int32)
  // Layout neuron-major, tal como especifica el PDF:
  //   peso capa1: addr = 64*n + i   (n en 0..15, i en 0..63)
  //   peso capa2: addr = 1024 + 16*n + i (n en 0..9, i en 0..15)
  //   bias: 0..15 capa1, 16..25 capa2
  // --------------------------------------------------------------------
    logic signed [7:0]  weight_rom  [0:1183];
    logic signed [31:0] bias_rom    [0:25];
    logic        [7:0]  n_oculta    [0:N_HID-1];

  initial begin
    $readmemh("weights.hex", weight_rom);
    $readmemh("biases.hex",  bias_rom);
  end

logic [4:0]     b_addr;
logic [10:0]    w_addr;
logic [3:0]     i_n;
logic [6:0]     i_i;
logic [2:0]     x, y;
logic           layer;
logic signed [31:0]    max, sum;
logic signed [15:0] prod;
logic [3:0]     best_idx;

// FIX: estos dependen de 'layer', que cambia en tiempo de ejecucion ->
// tienen que ser 'assign' (combinacional), no un valor inicial fijo.
logic [6:0] last_i_i;
logic [3:0] last_i_n;
assign last_i_i = layer ? (N_HID-1) : (N_IN-1);
assign last_i_n = layer ? (N_OUT-1) : (N_HID-1);

// Calculo de la direccion de Bias y peso de la neurona actual
// FIX: faltaba el offset de capa 2 (+16 bias, +1024 peso) y el indice i_i
assign b_addr = layer ? (5'd16 + i_n)              : i_n;
assign w_addr = layer ? (11'd1024 + i_n*16 + i_i)  : (i_n*64 + i_i);

// Valores de 0..7 en x/y (fila/columna dentro de la imagen 8x8)
assign x = i_i[2:0];   // columna
assign y = i_i[5:3];   // fila

// FIX: el operando de entrada debe venir del pixel (capa1) o de la
// activacion oculta (capa2), segun 'layer'. Antes SIEMPRE leia la imagen.
logic [7:0] x_val;
assign x_val = layer ? n_oculta[i_i[3:0]] : {4'b0, image[y][x]};

// FIX: 'prod' es puramente combinacional (assign) -> no se debe tocar
// tambien desde el always_ff (eso generaba dos drivers para la misma señal)
assign prod = weight_rom[w_addr] * $signed({1'b0, x_val});


localparam [2:0] IDDLE = 3'h0;
localparam [2:0] BIAS  = 3'h1;
localparam [2:0] L1    = 3'h2;
localparam [2:0] L2    = 3'h3;
localparam [2:0] DONE  = 3'h4;

logic       [2:0]   state;


always_ff @(posedge clk) begin
    if (rst) begin
        state    <= IDDLE;  // FIX: faltaba resetear el estado
        i_n      <= '0;
        i_i      <= '0;
        done     <= 1'b0;
        digit    <= '0;
        sum      <= '0;
        layer    <= 1'b0;
        max      <= '0;
        best_idx <= '0;
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

            // Calculo de neuronas (fase de acumulacion MAC)
            L1: begin
                sum <= sum + prod;
                if (i_i >= last_i_i) begin
                    state <= L2;
                end
                else begin
                    i_i <= i_i + 1'b1;
                end
            end

            // Post-proceso de fin de neurona (requant o argmax)
            L2: begin
                if (!layer) begin
                    logic signed [31:0] relu;
                    logic signed [31:0] shifted;
                    logic [7:0]         sat;

                    relu    = sum[31] ? 32'sd0 : sum;   // ReLU
                    // shifted = relu >>> SHIFT1;           // FIX: era >>4, debe ser >>5
                    sat     = ({{5{relu[31]}}, relu[31:5]} > 32'sd255) ? 8'hFF : relu[12:5]; // clamp

                    n_oculta[i_n] <= sat;

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
                        max      <= sum;    // FIX: era blocking (=), ahora <=
                        best_idx <= i_n;    // FIX: 'i_b' no existia, ahora best_idx
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
                digit <= {1'b0, best_idx};
                state <= IDDLE;  // FIX: era 'S_IDLE', no existia
            end

            default:
                state <= IDDLE;
        endcase
    end
end

endmodule