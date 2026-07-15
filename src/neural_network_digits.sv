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
    parameter int IMAGE_PIXEL_WIDTH     = 4,
    parameter int IMAGE_HORIZONTAL_SIZE = 8,
    parameter int IMAGE_VERTICAL_SIZE   = 8,
    parameter int DIGIT_WIDTH           = 5
)(
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic [IMAGE_PIXEL_WIDTH-1:0] image [IMAGE_HORIZONTAL_SIZE-1:0][IMAGE_VERTICAL_SIZE-1:0],
    output logic done,
    output logic [DIGIT_WIDTH-1:0] digit
);

  // --------------------------------------------------------------------
  // Parametros de la red (fijos por el proyecto)
  // --------------------------------------------------------------------
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
  logic signed [7:0]  weight_rom [0:1183];
  logic signed [31:0] bias_rom   [0:25];

  initial begin
    $readmemh("weights.hex", weight_rom);
    $readmemh("biases.hex",  bias_rom);
  end

  // --------------------------------------------------------------------
  // Memoria de activaciones de la capa oculta (uint8, post-requant)
  // --------------------------------------------------------------------
  logic [7:0] hidden_act [0:N_HID-1];

  // --------------------------------------------------------------------
  // FSM
  // --------------------------------------------------------------------
  typedef enum logic [2:0] {
    S_IDLE,
    S_LOAD_BIAS,
    S_ACC,
    S_POST,
    S_DONE
  } state_t;

  state_t state;

  logic        layer;       // 0 = capa1 (64->16), 1 = capa2 (16->10)
  logic [3:0]  neuron_idx;  // indice de neurona actual (0..15 o 0..9)
  logic [6:0]  input_idx;   // indice de entrada actual (0..63 o 0..15)
  logic signed [31:0] acc;  // acumulador de la pasada actual

  logic signed [31:0] best_score;
  logic [3:0]          best_idx;

  // Ultimo indice de entrada valido para la capa actual
  wire [6:0] last_input_idx = layer ? (N_HID-1) : (N_IN-1);
  wire [3:0] last_neuron_idx = layer ? (N_OUT-1) : (N_HID-1);

  // Direccion a la ROM de pesos, segun la capa
  wire [10:0] weight_addr = layer
      ? (11'd1024 + {7'd0, neuron_idx} * 16 + {4'd0, input_idx[3:0]})
      : ({7'd0, neuron_idx} * 64 + input_idx);

  // Direccion a la ROM de biases
  wire [4:0] bias_addr = layer ? (5'd16 + neuron_idx) : {1'b0, neuron_idx};

  // Operando "x" del MAC: pixel (capa1, uint4 -> se extiende a 8 bits sin
  // signo) o activacion oculta (capa2, uint8)
  logic [7:0] px_row, px_col;
  logic [7:0] x_val;
  always_comb begin
    px_row = input_idx[5:3];
    px_col = input_idx[2:0];
    x_val  = layer ? hidden_act[input_idx[3:0]]
                   : {4'b0, image[px_row[2:0]][px_col[2:0]]};
  end

  // Producto w*x (int8 con signo * valor no-negativo) -> cabe en 16 bits
  logic signed [7:0]  w_val;
  logic signed [15:0] product;
  assign w_val   = weight_rom[weight_addr];
  assign product = w_val * $signed({1'b0, x_val});

  // --------------------------------------------------------------------
  // Logica secuencial
  // --------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      state      <= S_IDLE;
      done       <= 1'b0;
      layer      <= 1'b0;
      neuron_idx <= '0;
      input_idx  <= '0;
      acc        <= '0;
      best_score <= '0;
      best_idx   <= '0;
      digit      <= '0;
    end else begin
      case (state)

        // ---------------------------------------------------------
        S_IDLE: begin
          done <= 1'b0;
          if (start) begin
            layer      <= 1'b0;
            neuron_idx <= '0;
            best_score <= 32'sh8000_0000; // minimo int32, garantiza 1er score gana
            state      <= S_LOAD_BIAS;
          end
        end

        // ---------------------------------------------------------
        S_LOAD_BIAS: begin
          acc       <= bias_rom[bias_addr];
          input_idx <= '0;
          state     <= S_ACC;
        end

        // ---------------------------------------------------------
        S_ACC: begin
          acc <= acc + product; // FMA: acc = acc + w[i]*x[i]
          if (input_idx == last_input_idx) begin
            state <= S_POST;
          end else begin
            input_idx <= input_idx + 1'b1;
          end
        end

        // ---------------------------------------------------------
        S_POST: begin
          if (!layer) begin
            // --- Fin de una neurona de la capa oculta: requant ---
            // ReLU
            logic signed [31:0] relu_val;
            logic signed [31:0] shifted;
            logic [7:0]         clamped;
            relu_val = acc[31] ? 32'sd0 : acc;      // signo -> 0
            shifted  = relu_val >>> SHIFT1;          // ya es >=0
            clamped  = (shifted > 32'sd255) ? 8'd255 : shifted[7:0];
            hidden_act[neuron_idx] <= clamped;

            if (neuron_idx == last_neuron_idx) begin
              layer      <= 1'b1;  // pasar a capa 2
              neuron_idx <= '0;
            end else begin
              neuron_idx <= neuron_idx + 1'b1;
            end
            state <= S_LOAD_BIAS;

          end else begin
            // --- Fin de una neurona de salida: argmax al vuelo ---
            if (acc > best_score) begin
              best_score <= acc;
              best_idx   <= neuron_idx;
            end

            if (neuron_idx == last_neuron_idx) begin
              state <= S_DONE;
            end else begin
              neuron_idx <= neuron_idx + 1'b1;
              state      <= S_LOAD_BIAS;
            end
          end
        end

        // ---------------------------------------------------------
        S_DONE: begin
          done  <= 1'b1;
          digit <= {1'b0, best_idx};
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule