module fpga_top (
    input  logic       clk,
    input  logic       rst_in,

    // Carga serial de la imagen
    input  logic [3:0] pixel_in,
    input  logic       pixel_valid,

    // Inicia la inferencia una vez cargados los 64 pixeles
    input  logic       start_in,

    output logic       done_out,
    output logic [4:0] digit_out
);

    //////////////////////////////////////////////////////
    // Parametros
    //////////////////////////////////////////////////////

    localparam int IMAGE_PIXEL_WIDTH     = 4;
    localparam int IMAGE_HORIZONTAL_SIZE = 8;
    localparam int IMAGE_VERTICAL_SIZE   = 8;
    localparam int DIGIT_WIDTH           = 5;
    localparam int NUM_PIXELS            = 64;

    //////////////////////////////////////////////////////
    // Buffer interno de imagen
    //////////////////////////////////////////////////////

    logic [IMAGE_PIXEL_WIDTH-1:0]
        image [IMAGE_HORIZONTAL_SIZE-1:0]
              [IMAGE_VERTICAL_SIZE-1:0];

    logic [5:0] pixel_count;

    //////////////////////////////////////////////////////
    // Carga de pixeles
    //////////////////////////////////////////////////////

    always_ff @(posedge clk) begin
        if (rst_in) begin
            pixel_count <= 6'd0;
        end
        else if (pixel_valid) begin

            image[pixel_count[5:3]]
                 [pixel_count[2:0]]
                 <= pixel_in;

            if (pixel_count != NUM_PIXELS-1)
                pixel_count <= pixel_count + 1'b1;
        end
    end

    //////////////////////////////////////////////////////
    // Instancia de la red neuronal
    //////////////////////////////////////////////////////

    logic done;
    logic [DIGIT_WIDTH-1:0] digit;

    neural_network_digits uut (
        .clk   (clk),
        .rst   (rst_in),
        .start (start_in),
        .image (image),
        .done  (done),
        .digit (digit)
    );

    //////////////////////////////////////////////////////
    // Registrar salidas para timing FPGA
    //////////////////////////////////////////////////////

    always_ff @(posedge clk) begin
        if (rst_in) begin
            done_out  <= 1'b0;
            digit_out <= '0;
        end
        else begin
            done_out  <= done;
            digit_out <= digit;
        end
    end

endmodule