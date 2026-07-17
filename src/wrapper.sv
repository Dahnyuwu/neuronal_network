module wrapper (
    input logic clk,
    input logic rst
);

    localparam int IMAGE_PIXEL_WIDTH     = 4;
    localparam int IMAGE_HORIZONTAL_SIZE = 8;
    localparam int IMAGE_VERTICAL_SIZE   = 8;
    localparam int DIGIT_WIDTH           = 5;

    // Entradas registradas
    logic start_r;

    logic [IMAGE_PIXEL_WIDTH-1:0]
        image_r [IMAGE_HORIZONTAL_SIZE-1:0][IMAGE_VERTICAL_SIZE-1:0];

    // Salidas del DUT
    logic done;
    logic [DIGIT_WIDTH-1:0] digit;

    // Salidas registradas
    logic done_r;
    logic [DIGIT_WIDTH-1:0] digit_r;

    integer x,y;

    always_ff @(posedge clk) begin
        start_r <= 1'b1;

        for (y=0; y<IMAGE_VERTICAL_SIZE; y=y+1)
            for (x=0; x<IMAGE_HORIZONTAL_SIZE; x=x+1)
                image_r[x][y] <= 4'd1;

        done_r  <= done;
        digit_r <= digit;
    end

    neural_network_digits dut (
        .clk   (clk),
        .rst   (rst),
        .start (start_r),
        .image (image_r),
        .done  (done),
        .digit (digit)
    );

endmodule