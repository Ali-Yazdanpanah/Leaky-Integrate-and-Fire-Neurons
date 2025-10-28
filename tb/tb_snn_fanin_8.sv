
`timescale 1ns/1ps
`include "../rtl/lif_pkg.vh"

module tb_snn_fanin_8;
  localparam int FAN_IN         = 8;
  localparam int NUM_NEURONS    = 1;
  localparam int CLK_HALF       = 5;
  localparam int MEASURE_CYCLES = 200000;
  localparam int MAX_DELAY      = 4;

  logic clk = 1'b0;
  always #CLK_HALF clk = ~clk;
  logic rst_n = 1'b0;

  logic [FAN_IN-1:0] poisson_spikes;

  genvar src_idx;
  generate
    for (src_idx = 0; src_idx < FAN_IN; src_idx++) begin : GEN_POISSON
      poisson_spike_gen #(.RATE(16'd3277)) u_src (
        .clk   (clk),
        .rst_n (rst_n),
        .spike (poisson_spikes[src_idx])
      );
    end
  endgenerate

  localparam logic signed [`W-1:0] WEIGHT_GRID [NUM_NEURONS][FAN_IN] = '{{default: `FX(0.05)}};
  localparam logic [7:0]           DELAY_GRID  [NUM_NEURONS][FAN_IN] = '{{default: 8'd0}};

  logic [NUM_NEURONS-1:0]            post_spikes;
  logic signed [`W-1:0]              post_vmem   [NUM_NEURONS];
  logic signed [`W-1:0]              dbg_exc     [NUM_NEURONS];
  logic signed [`W-1:0]              dbg_inh     [NUM_NEURONS];
  logic signed [`W-1:0]              dbg_i_total [NUM_NEURONS];

  snn_layer #(
    .NUM_INPUTS  (FAN_IN),
    .NUM_NEURONS (NUM_NEURONS),
    .MAX_DELAY   (MAX_DELAY),
    .W_INIT      (WEIGHT_GRID),
    .DELAY_INIT  (DELAY_GRID),
    .G_DECAY_E   (`FX(0.92)),
    .G_DECAY_I   (`FX(0.88)),
    .V_TH        (`FX(1.0)),
    .V_RESET     (`FX(0.0)),
    .V_REST      (`FX(0.0)),
    .LEAK_A      (`FX(0.96)),
    .REFR_TICKS  (4),
    .STDP_ENABLE (1'b0)
  ) u_layer (
    .clk           (clk),
    .rst_n         (rst_n),
    .pre_spikes    (poisson_spikes),
    .cfg_we        (1'b0),
    .cfg_sel_delay (1'b0),
    .cfg_addr      ('0),
    .cfg_wdata     ('0),
    .cfg_delay     (8'd0),
    .post_spikes   (post_spikes),
    .post_vmem     (post_vmem),
    .dbg_exc       (dbg_exc),
    .dbg_inh       (dbg_inh),
    .dbg_i_total   (dbg_i_total)
  );

  function automatic int popcount(input logic [FAN_IN-1:0] vec);
    int sum = 0;
    for (int i = 0; i < FAN_IN; i++) begin
      sum += vec[i];
    end
    return sum;
  endfunction

  time    input_fifo[$];
  integer cycle_ctr;
  integer total_input_events;
  integer total_output_spikes;
  real    latency_acc_ns;
  integer latency_samples;
  real    last_latency_ns;
  real    start_time_ns;
  bit     measuring;
  integer input_events;
  bit     spike;
  time    t_in;
  real    latency_ns;
  real    time_ns;

  integer csv_fd;

  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  initial begin
    string csv_name;
    csv_name = $sformatf("snn_fanin_trace_f8.csv");
    csv_fd = $fopen(csv_name, "w");
    if (csv_fd == 0) begin
      $fatal(1, "Failed to open %s", csv_name);
    end
    $display("Writing fan-in trace to %s", csv_name);
    $fdisplay(csv_fd, "cycle,time_ns,fan_in,input_events,output_spike,latency_ns");
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      cycle_ctr           <= 0;
      total_input_events  <= 0;
      total_output_spikes <= 0;
      latency_acc_ns      <= 0.0;
      latency_samples     <= 0;
      last_latency_ns     <= 0.0;
      measuring           <= 1'b0;
      input_fifo.delete();
    end else begin
      if (!measuring) begin
        measuring     <= 1'b1;
        start_time_ns <= $realtime;
      end

      cycle_ctr <= cycle_ctr + 1;

      input_events = popcount(poisson_spikes);
      total_input_events <= total_input_events + input_events;
      for (int evt = 0; evt < input_events; evt++) begin
        input_fifo.push_back($realtime);
      end

      spike = post_spikes[0];
      if (spike) begin
        total_output_spikes <= total_output_spikes + 1;
        if (input_fifo.size() > 0) begin
          t_in = input_fifo.pop_front();
          latency_ns = ($realtime - t_in);
          latency_acc_ns  <= latency_acc_ns + latency_ns;
          latency_samples <= latency_samples + 1;
          last_latency_ns <= latency_ns;
        end else begin
          last_latency_ns <= 0.0;
        end
      end else begin
        last_latency_ns <= 0.0;
      end

      time_ns = $realtime;
      $fdisplay(csv_fd,
                "%0d,%.3f,%0d,%0d,%0d,%.3f",
                cycle_ctr,
                time_ns,
                FAN_IN,
                input_events,
                spike,
                last_latency_ns);

      if (cycle_ctr >= MEASURE_CYCLES) begin
        real total_time_ns   = time_ns - start_time_ns;
        real throughput_meps = (total_time_ns > 0.0)
                                 ? (total_input_events * 1e3) / total_time_ns
                                 : 0.0;
        real mean_latency_ns = (latency_samples > 0)
                                 ? (latency_acc_ns / latency_samples)
                                 : 0.0;
        $display("FAN_IN=8 summary: input_events=%0d output_spikes=%0d", total_input_events, total_output_spikes);
        $display("Throughput = %.3f Mevents/s, Mean latency = %.3f ns", throughput_meps, mean_latency_ns);
        if (csv_fd) $fclose(csv_fd);
        $finish;
      end
    end
  end

endmodule
