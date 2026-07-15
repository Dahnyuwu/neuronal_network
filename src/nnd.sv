// ============================================================================
// neural_network_digits.sv
// Fase 1 -- implementacion COMPORTAMENTAL, Opcion A (un solo datapath reusado
// para ambas capas), cadena de FMA con N=1 (un MAC por ciclo).
//
// Topologia: 64 (pixeles 8x8, uint4) -> 16 (oculta, ReLU+>>5+clamp255) ->
//            10 (scores, sin ReLU) -> argmax
//
// Esta version prioriza claridad sobre desempeno: es el punto de partida
// antes de paralelizar con N>1 y arbol de compresores CSA.
// ============================================================================

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

    logic [6:0] last_i_i = layer ? (N_HID-1) : (N_IN-1);
    logic [3:0] last_i_n = layer ? (N_OUT-1) : (N_HID-1);

  // --------------------------------------------------------------------
  // Memorias: ROM de pesos (1184 x int8) y ROM de biases (26 x int32)
  // Layout neuron-major, tal como especifica el PDF:
  //   peso capa1: addr = 64*n + i   (n en 0..15, i en 0..63)
  //   peso capa2: addr = 1024 + 16*n + i (n en 0..9, i en 0..15)
  //   bias: 0..15 capa1, 16..25 capa2
  // --------------------------------------------------------------------
    logic signed [7:0]  weight_rom  [0:1183];
    logic signed [31:0] bias_rom    [0:25];
    logic        [7:0] n_oculta     [0:N_HID-1];


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
logic [31:0]    max, sum;
logic [15:0]    prod;

// Calculo de la direccion de Bias y peso de la neurona actual
assign b_addr    = i_n;
assign w_addr  = i_n * 64;


// Valores de 0..63 en x/y
assign x = i_i[2:0];
assign y = i_i[5:3];

// DUDA xd
assign prod = $signed({1'b0, image[x][y]}) * weight_rom[w_addr];


localparam [2:0] IDDLE = 3'h0;
localparam [2:0] BIAS  = 3'h1;
localparam [2:0] L1    = 3'h2;
localparam [2:0] L2    = 3'h3;
localparam [2:0] DONE  = 3'h4;

logic       [2:0]   state;



always_ff @(posedge clk) begin
    if (rst) begin
        i_n <= '0;
        i_i <= '0;
        done <= 1'b0;
        prod <= '0;
        sum <= '0;
        layer <= 1'b0;
        max <= '0;
    end

    else begin
        case (state)
            IDDLE: begin
                layer <= 1'b0;
                i_n <= '0;
                max <= 32'h8000_0000; // Mas negativo
                state <= BIAS;
            end

            BIAS: begin
                sum <= bias_rom[b_addr];
                i_i <= '0;
                state <= L1;
            end

            // Calculo de neuronas
            L1: begin
                sum <= sum + prod;
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
                    
                    relu = sum[31] ? '0: sum;
                    sat = (relu[31:4] > 8'hFF) ? 8'hFF : relu[11:4];
                    n_oculta[i_n] <= sat; 

                    if (i_n >= last_i_n) begin
                        layer <= 1'b1;
                        i_n <= '0;
                    end

                    else begin
                        i_n <= i_n + 1'b1;
                    end

                    state <= BIAS;
                    
                end

                else begin
                    if (sum > max) begin
                        max = sum;              // Sobre escribir la neurona mas grande
                        i_b = i_n;              // Guardar el index de neurona XD
                    end 

                    if (i_n == last_i_n) begin
                        state <= DONE;
                    end

                    else begin
                        i_n <= i_n + 1'b1;
                        state <= BIAS;
                    end
                end

            end

            DONE: begin
                done  <= 1'b1;
                digit <= {1'b0, best_idx};
                state <= S_IDLE;
            end

            default: 
                state <= IDDLE;
        endcase
    end
end

  endmodule