`timescale 1ns/1ps
`include "lif_pkg.vh"

module snn_layer #(
  parameter int NUM_INPUTS  = 2,
  parameter int NUM_NEURONS = 2,
  parameter int MAX_DELAY   = 4,
  parameter int CFG_ADDR_W  = ((NUM_NEURONS*NUM_INPUTS) > 1) ? $clog2(NUM_NEURONS*NUM_INPUTS) : 1,
  parameter logic signed [`W-1:0] W_INIT   [NUM_NEURONS][NUM_INPUTS]  = '{default: '{default: `FX(0.0)}},
  parameter logic [7:0]           DELAY_INIT[NUM_NEURONS][NUM_INPUTS] = '{default: '{default: 8'd0}},
  parameter logic signed [`W-1:0] G_DECAY_E = `FX(0.90),
  parameter logic signed [`W-1:0] G_DECAY_I = `FX(0.90),
  parameter signed [`W-1:0] V_TH    = `FX(1.0),
  parameter signed [`W-1:0] V_RESET = `FX(0.0),
  parameter signed [`W-1:0] V_REST  = `FX(0.0),
  parameter signed [`W-1:0] LEAK_A  = `FX(0.96),
  parameter int              REFR_TICKS = 2,
  parameter bit              STDP_ENABLE     = 1'b1,
  parameter logic signed [`W-1:0] STDP_A_PLUS  = `FX(0.002),
  parameter logic signed [`W-1:0] STDP_A_MINUS = `FX(0.003),
  parameter logic signed [`W-1:0] TRACE_DECAY_PRE  = `FX(0.95),
  parameter logic signed [`W-1:0] TRACE_DECAY_POST = `FX(0.95),
  parameter logic signed [`W-1:0] TRACE_INC_PRE   = `FX(1.0),
  parameter logic signed [`W-1:0] TRACE_INC_POST  = `FX(1.0),
  parameter logic signed [`W-1:0] W_MAX = `FX(0.75),
  parameter logic signed [`W-1:0] W_MIN = `FX(-0.75)
)(
  input  logic clk,
  input  logic rst_n,

  input  logic [NUM_INPUTS-1:0] pre_spikes,

  // simple config interface: address post*NUM_INPUTS + pre
  input  logic cfg_we,
  input  logic cfg_sel_delay,
  input  logic [CFG_ADDR_W-1:0] cfg_addr,
  input  logic signed [`W-1:0]  cfg_wdata,
  input  logic [7:0]            cfg_delay,

  output logic [NUM_NEURONS-1:0]               post_spikes,
  output logic signed [`W-1:0]                post_vmem   [NUM_NEURONS],
  output logic signed [`W-1:0]                dbg_exc     [NUM_NEURONS],
  output logic signed [`W-1:0]                dbg_inh     [NUM_NEURONS],
  output logic signed [`W-1:0]                dbg_i_total [NUM_NEURONS]
);
  typedef logic signed [`W-1:0] fx_t;
  typedef logic signed [(2*`W)-1:0] fx_wide_t;

  localparam int TOTAL_SYNAPSES = NUM_NEURONS * NUM_INPUTS;

  fx_t weights   [NUM_NEURONS][NUM_INPUTS];
  logic [7:0] delays [NUM_NEURONS][NUM_INPUTS];

  fx_t delay_line   [NUM_NEURONS][NUM_INPUTS][MAX_DELAY+1];
  fx_t delay_next   [NUM_NEURONS][NUM_INPUTS][MAX_DELAY+1];
  fx_t delivered_reg[NUM_NEURONS][NUM_INPUTS];

  fx_t g_exc     [NUM_NEURONS];
  fx_t g_inh     [NUM_NEURONS];
  fx_t g_exc_next[NUM_NEURONS];
  fx_t g_inh_next[NUM_NEURONS];
  fx_t i_curr    [NUM_NEURONS];

  fx_t pre_trace     [NUM_INPUTS];
  fx_t pre_trace_next[NUM_INPUTS];
  fx_t post_trace     [NUM_NEURONS];
  fx_t post_trace_next[NUM_NEURONS];
  logic [NUM_NEURONS-1:0] post_spike_reg;

  fx_t v_mem_int [NUM_NEURONS];

  function automatic fx_t clamp_weight(fx_t val);
    if (val > W_MAX) clamp_weight = W_MAX;
    else if (val < W_MIN) clamp_weight = W_MIN;
    else clamp_weight = val;
  endfunction

  // ------------------------------------------------------------
  // Delay pipelines - compute next state combinationally
  // ------------------------------------------------------------
  always_comb begin
    for (int n = 0; n < NUM_NEURONS; n++) begin
      for (int p = 0; p < NUM_INPUTS; p++) begin
        for (int stage = 0; stage < MAX_DELAY; stage++) begin
          delay_next[n][p][stage] = delay_line[n][p][stage+1];
        end
        delay_next[n][p][MAX_DELAY] = `FX(0.0);

        if (pre_spikes[p]) begin
          int idx;
          idx = (delays[n][p] > MAX_DELAY) ? MAX_DELAY : delays[n][p];
          delay_next[n][p][idx] = delay_next[n][p][idx] + weights[n][p];
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int n = 0; n < NUM_NEURONS; n++) begin
        for (int p = 0; p < NUM_INPUTS; p++) begin
          delivered_reg[n][p] <= `FX(0.0);
          for (int stage = 0; stage <= MAX_DELAY; stage++) begin
            delay_line[n][p][stage] <= `FX(0.0);
          end
        end
      end
    end else begin
      for (int n = 0; n < NUM_NEURONS; n++) begin
        for (int p = 0; p < NUM_INPUTS; p++) begin
          delivered_reg[n][p] <= delay_line[n][p][0];
          for (int stage = 0; stage <= MAX_DELAY; stage++) begin
            delay_line[n][p][stage] <= delay_next[n][p][stage];
          end
        end
      end
    end
  end

  // ------------------------------------------------------------
  // Conductance accumulation
  // ------------------------------------------------------------
  always_comb begin
    for (int n = 0; n < NUM_NEURONS; n++) begin
      fx_t exc_inject;
      fx_t inh_inject;
      fx_wide_t exc_prod;
      fx_wide_t inh_prod;
      fx_t exc_decay;
      fx_t inh_decay;

      exc_inject = `FX(0.0);
      inh_inject = `FX(0.0);

      for (int p = 0; p < NUM_INPUTS; p++) begin
        fx_t contrib;
        contrib = delivered_reg[n][p];
        if (contrib[`W-1])
          inh_inject += -contrib;
        else
          exc_inject += contrib;
      end

      exc_prod = $signed(g_exc[n]) * $signed(G_DECAY_E);
      inh_prod = $signed(g_inh[n]) * $signed(G_DECAY_I);

      exc_decay = exc_prod >>> `Q;
      inh_decay = inh_prod >>> `Q;

      g_exc_next[n] = exc_decay + exc_inject;
      g_inh_next[n] = inh_decay + inh_inject;
      i_curr[n]     = g_exc_next[n] - g_inh_next[n];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int n = 0; n < NUM_NEURONS; n++) begin
        g_exc[n] <= `FX(0.0);
        g_inh[n] <= `FX(0.0);
      end
    end else begin
      for (int n = 0; n < NUM_NEURONS; n++) begin
        g_exc[n] <= g_exc_next[n];
        g_inh[n] <= g_inh_next[n];
      end
    end
  end

  assign dbg_exc     = g_exc;
  assign dbg_inh     = g_inh;
  assign dbg_i_total = i_curr;

  // ------------------------------------------------------------
  // Spike traces for STDP
  // ------------------------------------------------------------
  always_comb begin
    for (int p = 0; p < NUM_INPUTS; p++) begin
      fx_wide_t pre_prod;
      pre_prod = $signed(pre_trace[p]) * $signed(TRACE_DECAY_PRE);
      pre_trace_next[p] = pre_prod >>> `Q;
      if (pre_spikes[p])
        pre_trace_next[p] = pre_trace_next[p] + TRACE_INC_PRE;
    end

    for (int n = 0; n < NUM_NEURONS; n++) begin
      fx_wide_t post_prod;
      post_prod = $signed(post_trace[n]) * $signed(TRACE_DECAY_POST);
      post_trace_next[n] = post_prod >>> `Q;
      if (post_spike_reg[n])
        post_trace_next[n] = post_trace_next[n] + TRACE_INC_POST;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int p = 0; p < NUM_INPUTS; p++) begin
        pre_trace[p] <= `FX(0.0);
      end
      for (int n = 0; n < NUM_NEURONS; n++) begin
        post_trace[n]   <= `FX(0.0);
        post_spike_reg[n] <= 1'b0;
      end
    end else begin
      for (int p = 0; p < NUM_INPUTS; p++) begin
        pre_trace[p] <= pre_trace_next[p];
      end
      post_spike_reg <= post_spikes;
      for (int n = 0; n < NUM_NEURONS; n++) begin
        post_trace[n] <= post_trace_next[n];
      end
    end
  end

  // ------------------------------------------------------------
  // Weight / delay storage with STDP updates
  // ------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int n = 0; n < NUM_NEURONS; n++) begin
        for (int p = 0; p < NUM_INPUTS; p++) begin
          weights[n][p] <= W_INIT[n][p];
          delays [n][p] <= DELAY_INIT[n][p];
        end
      end
    end else begin
      for (int n = 0; n < NUM_NEURONS; n++) begin
        for (int p = 0; p < NUM_INPUTS; p++) begin
          fx_t new_w;
          new_w = weights[n][p];
          if (STDP_ENABLE) begin
            if (delivered_reg[n][p] != fx_t'(0)) begin
              fx_wide_t dw_minus_full;
              fx_t dw_minus;
              dw_minus_full = $signed(post_trace[n]) * $signed(STDP_A_MINUS);
              dw_minus = dw_minus_full >>> `Q;
              new_w = new_w - dw_minus;
            end
            if (post_spike_reg[n]) begin
              fx_wide_t dw_plus_full;
              fx_t dw_plus;
              dw_plus_full = $signed(pre_trace[p]) * $signed(STDP_A_PLUS);
              dw_plus = dw_plus_full >>> `Q;
              new_w = new_w + dw_plus;
            end
          end
          weights[n][p] <= clamp_weight(new_w);
        end
      end

      if (cfg_we) begin
        int cfg_post = cfg_addr / NUM_INPUTS;
        int cfg_pre  = cfg_addr % NUM_INPUTS;
        if (cfg_post < NUM_NEURONS && cfg_pre < NUM_INPUTS) begin
          if (cfg_sel_delay)
            delays[cfg_post][cfg_pre] <= cfg_delay;
          else
            weights[cfg_post][cfg_pre] <= cfg_wdata;
        end
      end
    end
  end

  // ------------------------------------------------------------
  // Instantiate neurons
  // ------------------------------------------------------------
  genvar n_idx;
  generate
    for (n_idx = 0; n_idx < NUM_NEURONS; n_idx++) begin : GEN_NEURON
      lif_neuron #(
        .V_TH(V_TH),
        .V_RESET(V_RESET),
        .V_REST(V_REST),
        .LEAK_A(LEAK_A),
        .REFR_TICKS(REFR_TICKS)
      ) u_neuron (
        .clk    (clk),
        .rst_n  (rst_n),
        .i_in   (i_curr[n_idx]),
        .spike  (post_spikes[n_idx]),
        .v_mem  (v_mem_int[n_idx])
      );
    end
  endgenerate

  assign post_vmem = v_mem_int;

endmodule
