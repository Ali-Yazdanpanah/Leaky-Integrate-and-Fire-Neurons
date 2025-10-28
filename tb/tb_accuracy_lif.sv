`timescale 1ns/1ps
`include "../rtl/lif_pkg.vh"

module tb_accuracy_lif;
  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------
  localparam int CLOCK_HZ        = 100_000_000;          // 100 MHz
  localparam int SAMPLE_SECONDS  = 1;                     // run duration
  localparam int TOTAL_TICKS     = CLOCK_HZ * SAMPLE_SECONDS;
  localparam real DT_SEC         = 1.0 / CLOCK_HZ;
  localparam real INPUT_RATE_HZ  = 200.0;                // Poisson drive
  localparam int TOLERANCE_TICKS = 50000; // +/- 0.5 ms window

  localparam signed [`W-1:0] STIM_WEIGHT = `FX(0.35);

  // ---------------------------------------------------------------------------
  // Clock / reset
  // ---------------------------------------------------------------------------
  logic clk = 1'b0;
  always #5 clk = ~clk; // 100 MHz

  logic rst_n = 1'b0;
  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  // ---------------------------------------------------------------------------
  // Poisson stimulus (32-bit LFSR + threshold)
  // ---------------------------------------------------------------------------
  reg [31:0] lfsr;
  integer poisson_threshold;
  logic poisson_spike;

  function automatic logic feedback(input logic [31:0] state);
    feedback = state[31] ^ state[21] ^ state[1] ^ state[0];
  endfunction

  initial begin
    lfsr               = 32'hACE1_F1E2;
    poisson_threshold  = $rtoi((INPUT_RATE_HZ / $itor(CLOCK_HZ)) * 4294967295.0 + 0.5);
    poisson_spike      = 1'b0;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lfsr          <= 32'hACE1_F1E2;
      poisson_spike <= 1'b0;
    end else begin
      lfsr          <= {lfsr[30:0], feedback(lfsr)};
      poisson_spike <= ($unsigned(lfsr) <= poisson_threshold);
    end
  end

  // ---------------------------------------------------------------------------
  // DUT: Q4.12 LIF neuron
  // ---------------------------------------------------------------------------
  logic signed [`W-1:0] i_in_fx;
  wire signed [`W-1:0] v_mem_fx;
  wire spike_hw;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      i_in_fx <= `FX(0.0);
    else
      i_in_fx <= poisson_spike ? STIM_WEIGHT : `FX(0.0);
  end

  lif_neuron #(
    .V_TH      (`FX(1.0)),
    .V_RESET   (`FX(0.0)),
    .V_REST    (`FX(0.0)),
    .LEAK_A    (`FX(0.96)),
    .REFR_TICKS(2)
  ) dut (
    .clk   (clk),
    .rst_n (rst_n),
    .i_in  (i_in_fx),
    .spike (spike_hw),
    .v_mem (v_mem_fx)
  );

  // ---------------------------------------------------------------------------
  // Double-precision reference model
  // ---------------------------------------------------------------------------
  real v_ref;
  int  refr_ctr_ref;
  logic spike_ref;

  function real fx_to_real(input signed [`W-1:0] val);
    fx_to_real = $itor(val) / $itor(1 << `Q);
  endfunction

  function real leak_step(real v_current, real i_current);
    real alpha;
    begin
      alpha    = fx_to_real(`FX(0.96));
      leak_step = fx_to_real(`FX(0.0)) + alpha * (v_current - fx_to_real(`FX(0.0))) + i_current;
    end
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      v_ref        <= fx_to_real(`FX(0.0));
      refr_ctr_ref <= 0;
      spike_ref    <= 1'b0;
    end else begin
      real i_real;
      real next_v;
      spike_ref <= 1'b0;
      i_real    = fx_to_real(i_in_fx);

      if (refr_ctr_ref != 0) begin
        refr_ctr_ref <= refr_ctr_ref - 1;
        v_ref        <= fx_to_real(`FX(0.0));
      end else begin
        next_v = leak_step(v_ref, i_real);
        if (next_v >= fx_to_real(`FX(1.0))) begin
          spike_ref    <= 1'b1;
          v_ref        <= fx_to_real(`FX(0.0));
          refr_ctr_ref <= 2;
        end else begin
          v_ref <= next_v;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Metrics collection
  // ---------------------------------------------------------------------------
  integer cycle_cnt;
  localparam integer MAX_SPIKES = 2000;
  integer hw_spike_times [0:MAX_SPIKES-1];
  integer ref_spike_times[0:MAX_SPIKES-1];
  integer hw_spike_count;
  integer ref_spike_count;
  integer sample_count;
  real sum_sq_error;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_cnt      <= 0;
      sample_count   <= 0;
      sum_sq_error   <= 0.0;
      hw_spike_count <= 0;
      ref_spike_count <= 0;
    end else begin
      cycle_cnt    <= cycle_cnt + 1;
      sample_count <= sample_count + 1;
      sum_sq_error <= sum_sq_error + (fx_to_real(v_mem_fx) - v_ref) * (fx_to_real(v_mem_fx) - v_ref);
      if (spike_hw && hw_spike_count < MAX_SPIKES) begin
        hw_spike_times[hw_spike_count] <= cycle_cnt;
        hw_spike_count <= hw_spike_count + 1;
      end
      if (spike_ref && ref_spike_count < MAX_SPIKES) begin
        ref_spike_times[ref_spike_count] <= cycle_cnt;
        ref_spike_count <= ref_spike_count + 1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Metric helpers
  // ---------------------------------------------------------------------------
  task automatic compute_metrics (
    input int match_count,
    input int positives_hw,
    input int positives_ref,
    output real precision,
    output real recall,
    output real f1
  );
    begin
      precision = (positives_hw > 0) ? match_count / $itor(positives_hw) : 0.0;
      recall    = (positives_ref > 0) ? match_count / $itor(positives_ref) : 0.0;
      if ((precision + recall) > 0.0)
        f1 = (2.0 * precision * recall) / (precision + recall);
      else
        f1 = 0.0;
    end
  endtask

  function automatic int count_matches (
    input int hw_count,
    input int ref_count,
    input int tolerance
  );
    int i;
    int j;
    int m;
    int diff;
    begin
      i = 0;
      j = 0;
      m = 0;
      while ((i < hw_count) && (j < ref_count)) begin
        diff = hw_spike_times[i] - ref_spike_times[j];
        if ((diff <= tolerance) && (diff >= -tolerance)) begin
          m = m + 1;
          i = i + 1;
          j = j + 1;
        end else if (diff < 0)
          i = i + 1;
        else
          j = j + 1;
      end
      count_matches = m;
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Final reporting
  // ---------------------------------------------------------------------------
  task automatic finalize_results;
    int match_count;
    real precision;
    real recall;
    real f1;
    real rmse;
    real mis_rate;
    integer fd;
    begin
      match_count = count_matches(hw_spike_count, ref_spike_count, TOLERANCE_TICKS);
      compute_metrics(match_count, hw_spike_count, ref_spike_count, precision, recall, f1);
      rmse     = (sample_count > 0) ? $sqrt(sum_sq_error / $itor(sample_count)) : 0.0;
      mis_rate = (ref_spike_count > 0) ? 1.0 - (match_count / $itor(ref_spike_count)) : 0.0;

      fd = $fopen("scripts/accuracy_metrics.csv", "w");
      if (fd == 0)
        fd = $fopen("accuracy_metrics.csv", "w");
      if (fd != 0) begin
        $fdisplay(fd, "duration_s,input_rate_hz,stim_weight_q4_12,hw_spikes,ref_spikes,matches,precision,recall,f1,mis_rate,rmse");
        $fdisplay(fd,
                  "%0d,%0.2f,%0.6f,%0d,%0d,%0d,%0.6f,%0.6f,%0.6f,%0.6f,%0.6f",
                  SAMPLE_SECONDS,
                  INPUT_RATE_HZ,
                  fx_to_real(STIM_WEIGHT),
                  hw_spike_count,
                  ref_spike_count,
                  match_count,
                  precision,
                  recall,
                  f1,
                  mis_rate,
                  rmse);
        $fclose(fd);
      end

      $display("==== Accuracy Bench Summary ====");
      $display("Sim duration       : %0d s", SAMPLE_SECONDS);
      $display("Input rate (Hz)    : %0.2f", INPUT_RATE_HZ);
      $display("Stimulus weight    : %0.6f (Q4.12)", fx_to_real(STIM_WEIGHT));
      $display("Hardware spikes    : %0d", hw_spike_count);
      $display("Reference spikes   : %0d", ref_spike_count);
      $display("Matched spikes     : %0d (+/-%0.3f ms window)", match_count, TOLERANCE_TICKS * DT_SEC * 1e3);
      $display("Precision          : %0.6f", precision);
      $display("Recall             : %0.6f", recall);
      $display("F1 score           : %0.6f", f1);
      $display("Misclassification  : %0.6f", mis_rate);
      $display("Membrane RMSE (V)  : %0.6f", rmse);
    end
  endtask

  bit finished;
  always @(posedge clk) begin
    if (rst_n && !finished && (cycle_cnt >= TOTAL_TICKS)) begin
      finished = 1'b1;
      finalize_results();
      $finish;
    end
  end

endmodule
