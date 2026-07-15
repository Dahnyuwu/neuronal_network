// Self-checking testbench for neural_network_digits.
//
// Implementation-agnostic by design: the only contract with the DUT is
//   1) drive `image` and keep it stable during the inference
//   2) pulse `start` for a single cycle while the DUT is idle
//   3) wait for `done` (however many cycles that takes) and sample `digit`
//
// Pass criterion: `digit` must match test_golden.txt (the bit-exact integer
// model, infer_int) on all images. Accuracy vs test_labels.txt is reported
// as information only (expected 47/50 = 94%).
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

  // Test vectors
  logic [3:0] test_pixels [0:(NUM_TEST_IMAGES * IMAGE_NUM_PIXELS)-1];
  int         labels      [0:NUM_TEST_IMAGES-1];
  int         golden      [0:NUM_TEST_IMAGES-1];

  int golden_mismatches = 0;
  int label_hits        = 0;

  neural_network_digits dut (
    .clk  (clk),
    .rst  (rst),
    .start(start),
    .image(image),
    .done (done),
    .digit(digit)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic load_files();
    int fd, code;
    $readmemh("test_images.hex", test_pixels);
    fd = $fopen("test_labels.txt", "r");
    if (fd == 0) $fatal(1, "cannot open test_labels.txt");
    for (int i = 0; i < NUM_TEST_IMAGES; i++) code = $fscanf(fd, "%d\n", labels[i]);
    $fclose(fd);
    fd = $fopen("test_golden.txt", "r");
    if (fd == 0) $fatal(1, "cannot open test_golden.txt");
    for (int i = 0; i < NUM_TEST_IMAGES; i++) code = $fscanf(fd, "%d\n", golden[i]);
    $fclose(fd);
  endtask

  task automatic run_inference(input int img_idx, output logic [3:0] predicted, output int cycles);
    // The DUT reads the image throughout layer 1: drive it and hold it stable
    for (int px = 0; px < IMAGE_NUM_PIXELS; px++) begin
      image[px / 8][px % 8] = test_pixels[(img_idx * IMAGE_NUM_PIXELS) + px];
    end
    @(posedge clk);
    start <= 1'b1;      // single-cycle pulse, per the DUT contract
    @(posedge clk);
    start <= 1'b0;
    cycles = 0;
    while (!done) begin // implementation-agnostic: wait as long as it takes
      @(posedge clk);
      cycles++;
      if (cycles > TIMEOUT_CYCLES) begin
        $fatal(1, "img %0d: TIMEOUT after %0d cycles, done never asserted", img_idx, cycles);
      end
    end
    predicted = digit;
    @(posedge clk);     // let the FSM drain back to IDLE before the next start
  endtask

  initial begin
    logic [3:0] predicted;
    int cycles;

    start = 1'b0;
    rst   = 1'b1;
    repeat (3) @(posedge clk);
    rst = 1'b0;

    load_files();

    for (int i = 0; i < NUM_TEST_IMAGES; i++) begin
      run_inference(i, predicted, cycles);
      if (predicted !== golden[i][3:0]) begin
        golden_mismatches++;
        $display("img %2d: FAIL  digit=%0d golden=%0d label=%0d (%0d cycles)",
                 i, predicted, golden[i], labels[i], cycles);
      end else begin
        $display("img %2d: pass  digit=%0d label=%0d (%0d cycles)",
                 i, predicted, labels[i], cycles);
      end
      if (predicted == labels[i][3:0]) label_hits++;
    end

    $display("--------------------------------------------------------");
    $display("golden matches : %0d/%0d (must be %0d)",
             NUM_TEST_IMAGES - golden_mismatches, NUM_TEST_IMAGES, NUM_TEST_IMAGES);
    $display("label accuracy : %0d/%0d (expected 47/50)", label_hits, NUM_TEST_IMAGES);
    if (golden_mismatches == 0) begin
      $display("TEST PASSED");
    end else begin
      $display("TEST FAILED: %0d mismatches vs golden model", golden_mismatches);
    end
    $finish;
  end

endmodule
