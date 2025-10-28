`timescale 1ns/1ps
`include "../rtl/lif_pkg.vh"

module tb_snn_simple;
  localparam CLK_HALF = 5; // 100 MHz
  reg clk=0; always #CLK_HALF clk = ~clk;

  reg rstn=0;
  wire in0_spk, in1_spk;
  // input rates: ~5% and ~8% per tick (tune these)
  poisson_spike_gen #(.RATE(16'd3277)) IN0 (.clk(clk), .rst_n(rstn), .spike(in0_spk));
  poisson_spike_gen #(.RATE(16'd5243)) IN1 (.clk(clk), .rst_n(rstn), .spike(in1_spk));

  wire n0_spk, n1_spk;
  wire signed [`W-1:0] n0_v, n1_v;

  snn_simple #(
    .REFR_TICKS(4),
    .DELAY01  (8'd3),
    .DELAY10  (8'd5),
    .G_DECAY_E(`FX(0.92)),
    .G_DECAY_I(`FX(0.88))
  ) DUT (
    .clk(clk), .rst_n(rstn),
    .in0_spike(in0_spk), .in1_spike(in1_spk),
    .n0_spike(n0_spk), .n1_spike(n1_spk),
    .n0_vmem(n0_v), .n1_vmem(n1_v)
  );

  integer c0=0, c1=0;
  integer csv_fd;
  integer sim_cycles;
  integer cycle_ctr;

  function real fx_to_real(input signed [`W-1:0] val);
    fx_to_real = val / (1.0 * (1 << `Q));
  endfunction

  always @(posedge clk) begin
    if (n0_spk) c0 <= c0 + 1;
    if (n1_spk) c1 <= c1 + 1;
    if (rstn) begin
      cycle_ctr <= cycle_ctr + 1;
      if (csv_fd)
        $fwrite(csv_fd, "%0d,%0f,%0d,%0d,%0d,%0d,%f,%f\n",
                cycle_ctr,
                $realtime,
                in0_spk,
                in1_spk,
                n0_spk,
                n1_spk,
                fx_to_real(n0_v),
                fx_to_real(n1_v));
    end else begin
      cycle_ctr <= 0;
    end
  end

  initial begin
    // VCD for quick plotting; Vivado will also produce WDB
    $dumpfile("snn_simple.vcd"); $dumpvars(0, tb_snn_simple);

    csv_fd = $fopen("snn_simple_trace.csv", "w");
    if (csv_fd == 0) begin
      $fatal(1, "Failed to open snn_simple_trace.csv");
    end
    $fdisplay(csv_fd,
              "cycle,time_ns,in0_spk,in1_spk,n0_spk,n1_spk,n0_v_real,n1_v_real");

    // reset
    repeat(10) @(posedge clk);
    rstn = 1;

    // run for some time to accumulate spikes
    repeat(200000) @(posedge clk); // 2 ms at 100 MHz

    $display("Neuron0 spikes: %0d", c0);
    $display("Neuron1 spikes: %0d", c1);
    report_weights();
    if (csv_fd) $fclose(csv_fd);
    $finish;
  end

  task report_weights;
    real w00, w01, w10, w11;
    begin
      w00 = fx_to_real(DUT.u_layer.weights[0][0]);
      w01 = fx_to_real(DUT.u_layer.weights[0][1]);
      w10 = fx_to_real(DUT.u_layer.weights[1][0]);
      w11 = fx_to_real(DUT.u_layer.weights[1][1]);

      $display("Final weights:");
      $display("  W00=%.3f W01=%.3f", w00, w01);
      $display("  W10=%.3f W11=%.3f", w10, w11);
    end
  endtask
endmodule
