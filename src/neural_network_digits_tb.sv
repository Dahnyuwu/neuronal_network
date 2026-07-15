`timescale 1ns/1ps

module neural_network_digits_tb;

  localparam int NUM_TEST_IMAGES  = 50;
  localparam int IMAGE_NUM_PIXELS = 64;
  localparam int TIMEOUT_CYCLES   = 100000;

  logic       clk;
  logic       rst;
  logic       start;
  logic       done;
  logic [3:0] digit;
  logic [3:0] image [7:0][7:0];

  //============================================================
  // Test vectors
  //============================================================
  logic [3:0] test_pixels [0:(NUM_TEST_IMAGES * IMAGE_NUM_PIXELS)-1];
  int         labels      [0:NUM_TEST_IMAGES-1];
  int         golden      [0:NUM_TEST_IMAGES-1];

  int golden_mismatches = 0;
  int label_hits        = 0;

  //============================================================
  // Debug
  //============================================================
  integer dbg_best_idx;
  integer dbg_best_val;

  //============================================================
  // DUT
  //============================================================
  neural_network_digits dut (
    .clk   (clk),
    .rst   (rst),
    .start (start),
    .image (image),
    .done  (done),
    .digit (digit)
  );

  //============================================================
  // Clock
  //============================================================
  initial clk = 0;
  always #5 clk = ~clk;

  //============================================================
  // Debug init
  //============================================================
  initial begin
    dbg_best_idx = -1;
    dbg_best_val = -2147483648;
  end

  //============================================================
  // Imprimir imagen 8x8
  //============================================================
  task automatic print_input_image();

    $display("INPUT IMAGE");

    for (int r = 0; r < 8; r++) begin
      $display(
        "%1d %1d %1d %1d %1d %1d %1d %1d",
        image[r][0],
        image[r][1],
        image[r][2],
        image[r][3],
        image[r][4],
        image[r][5],
        image[r][6],
        image[r][7]
      );
    end

  endtask

  //============================================================
  // DEBUG PRIMERA CAPA
  //============================================================
  always @(posedge clk) begin

    if (!rst &&
        dut.state == dut.L1 &&
        dut.layer == 1'b0) begin

      $display(
        "[%0t] L1  neuron=%0d  pixel=%0d  xy=(%0d,%0d) input=%0d weight=%0d prod=%0d sum=%0d",
        $time,
        dut.i_n,
        dut.i_i,
        dut.x,
        dut.y,
        dut.image[dut.y][dut.x],
        dut.weight_rom[dut.w_addr],
        dut.prod,
        dut.sum
      );
    end

  end

  //============================================================
  // DEBUG CAPA OCULTA
  //============================================================
  always @(posedge clk) begin

    int idx;

    if (!rst &&
        dut.state == dut.L2 &&
        dut.layer == 1'b0) begin

      idx = dut.i_n;

      #1;

      $display(
        "[%0t] Hidden[%0d] = %0d (0x%02h) sum=%0d",
        $time,
        idx,
        dut.n_oculta[idx],
        dut.n_oculta[idx],
        dut.sum
      );
    end

  end

  //============================================================
  // DEBUG CAPA DE SALIDA
  //============================================================
  always @(posedge clk) begin

    int idx;

    if (!rst &&
        dut.state == dut.L2 &&
        dut.layer == 1'b1) begin

      idx = dut.i_n;

      if (dut.sum > dbg_best_val) begin
        dbg_best_val = dut.sum;
        dbg_best_idx = idx;
      end

      $display(
        "[%0t] Output[%0d] = %0d   current_best=(digit=%0d value=%0d)",
        $time,
        idx,
        dut.sum,
        dbg_best_idx,
        dbg_best_val
      );
    end

  end

  //============================================================
  // Resultado final
  //============================================================
  always @(posedge clk) begin

    if (!rst && done) begin

      $display("------------------------------------------------");
      $display("OUTPUT LAYER WINNER");
      $display("Winner neuron : %0d", dbg_best_idx);
      $display("Winner value  : %0d", dbg_best_val);
      $display("Digit output  : %0d", digit);
      $display("------------------------------------------------");

      dbg_best_idx = -1;
      dbg_best_val = -2147483648;
    end

  end

  //============================================================
  // Carga archivos
  //============================================================
  task automatic load_files();

    int fd;
    int code;

    $readmemh("test_images.hex", test_pixels);

    fd = $fopen("test_labels.txt", "r");
    if (fd == 0)
      $fatal(1, "cannot open test_labels.txt");

    for (int i = 0; i < NUM_TEST_IMAGES; i++)
      code = $fscanf(fd, "%d\n", labels[i]);

    $fclose(fd);

    fd = $fopen("test_golden.txt", "r");
    if (fd == 0)
      $fatal(1, "cannot open test_golden.txt");

    for (int i = 0; i < NUM_TEST_IMAGES; i++)
      code = $fscanf(fd, "%d\n", golden[i]);

    $fclose(fd);

  endtask

  //============================================================
  // Inferencia
  //============================================================
  task automatic run_inference(
    input int img_idx,
    output logic [3:0] predicted,
    output int cycles
  );

    for (int px = 0; px < IMAGE_NUM_PIXELS; px++) begin
      image[px/8][px%8] =
        test_pixels[(img_idx * IMAGE_NUM_PIXELS) + px];
    end

    print_input_image();

    @(posedge clk);
    start <= 1'b1;

    @(posedge clk);
    start <= 1'b0;

    cycles = 0;

    while (!done) begin

      @(posedge clk);
      cycles++;

      if (cycles > TIMEOUT_CYCLES) begin
        $fatal(
          1,
          "img %0d: TIMEOUT after %0d cycles",
          img_idx,
          cycles
        );
      end

    end

    predicted = digit;

    @(posedge clk);

  endtask

  //============================================================
  // Test principal
  //============================================================
  initial begin

    logic [3:0] predicted;
    int cycles;

    start = 1'b0;
    rst   = 1'b1;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    load_files();

    for (int i = 0; i < NUM_TEST_IMAGES; i++) begin

      $display("");
      $display("========================================================");
      $display("IMAGE %0d", i);
      $display("========================================================");

      run_inference(i, predicted, cycles);

      if (predicted !== golden[i][3:0]) begin

        golden_mismatches++;

        $display(
          "img %2d: FAIL digit=%0d golden=%0d label=%0d (%0d cycles)",
          i,
          predicted,
          golden[i],
          labels[i],
          cycles
        );

      end
      else begin

        $display(
          "img %2d: PASS digit=%0d label=%0d (%0d cycles)",
          i,
          predicted,
          labels[i],
          cycles
        );

      end

      if (predicted == labels[i][3:0])
        label_hits++;

    end

    $display("--------------------------------------------------------");

    $display(
      "golden matches : %0d/%0d (must be %0d)",
      NUM_TEST_IMAGES - golden_mismatches,
      NUM_TEST_IMAGES,
      NUM_TEST_IMAGES
    );

    $display(
      "label accuracy : %0d/%0d (expected 47/50)",
      label_hits,
      NUM_TEST_IMAGES
    );

    if (golden_mismatches == 0)
      $display("TEST PASSED");
    else
      $display(
        "TEST FAILED: %0d mismatches vs golden model",
        golden_mismatches
      );

    $finish;

  end

endmodule