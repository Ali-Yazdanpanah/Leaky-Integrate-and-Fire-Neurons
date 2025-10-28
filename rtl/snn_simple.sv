`timescale 1ns/1ps
`include "lif_pkg.vh"

module snn_simple #(
  parameter signed [`W-1:0] W00 = `FX(0.30),
  parameter signed [`W-1:0] W01 = `FX(0.10),
  parameter signed [`W-1:0] W10 = `FX(-0.05),
  parameter signed [`W-1:0] W11 = `FX(0.35),
  parameter signed [`W-1:0] V_TH    = `FX(1.0),
  parameter signed [`W-1:0] V_RESET = `FX(0.0),
  parameter signed [`W-1:0] V_REST  = `FX(0.0),
  parameter signed [`W-1:0] LEAK_A  = `FX(0.96),
  parameter int              REFR_TICKS = 2,
  parameter logic signed [`W-1:0] G_DECAY_E = `FX(0.90),
  parameter logic signed [`W-1:0] G_DECAY_I = `FX(0.90),
  parameter logic [7:0] DELAY00 = 8'd0,
  parameter logic [7:0] DELAY01 = 8'd0,
  parameter logic [7:0] DELAY10 = 8'd0,
  parameter logic [7:0] DELAY11 = 8'd0
)(
  input  logic clk,
  input  logic rst_n,
  input  logic in0_spike,
  input  logic in1_spike,
  output logic n0_spike,
  output logic n1_spike,
  output logic signed [`W-1:0] n0_vmem,
  output logic signed [`W-1:0] n1_vmem,
  output logic signed [`W-1:0] n0_i_total,
  output logic signed [`W-1:0] n1_i_total,
  output logic signed [`W-1:0] n0_g_exc,
  output logic signed [`W-1:0] n1_g_exc,
  output logic signed [`W-1:0] n0_g_inh,
  output logic signed [`W-1:0] n1_g_inh
);
  localparam int NUM_INPUTS  = 2;
  localparam int NUM_NEURONS = 2;
  localparam int MAX_DELAY   = 8;

  logic [NUM_INPUTS-1:0] presyn_bus;
  assign presyn_bus = {in1_spike, in0_spike};

  logic [NUM_NEURONS-1:0] postsyn_spikes;
  logic signed [`W-1:0]   postsyn_vmem [NUM_NEURONS];
  logic signed [`W-1:0]   dbg_exc      [NUM_NEURONS];
  logic signed [`W-1:0]   dbg_inh      [NUM_NEURONS];
  logic signed [`W-1:0]   dbg_i_total  [NUM_NEURONS];

  localparam logic signed [`W-1:0] WEIGHTS   [NUM_NEURONS][NUM_INPUTS] = '{
    '{W00, W01},
    '{W10, W11}
  };
  localparam logic [7:0] DELAYS [NUM_NEURONS][NUM_INPUTS] = '{
    '{DELAY00, DELAY01},
    '{DELAY10, DELAY11}
  };

  snn_layer #(
    .NUM_INPUTS (NUM_INPUTS),
    .NUM_NEURONS(NUM_NEURONS),
    .MAX_DELAY  (MAX_DELAY),
    .W_INIT     (WEIGHTS),
    .DELAY_INIT (DELAYS),
    .G_DECAY_E  (G_DECAY_E),
    .G_DECAY_I  (G_DECAY_I),
    .V_TH       (V_TH),
    .V_RESET    (V_RESET),
    .V_REST     (V_REST),
    .LEAK_A     (LEAK_A),
    .REFR_TICKS (REFR_TICKS)
  ) u_layer (
    .clk          (clk),
    .rst_n        (rst_n),
    .pre_spikes   (presyn_bus),
    .cfg_we       (1'b0),
    .cfg_sel_delay(1'b0),
    .cfg_addr     ('0),
    .cfg_wdata    ('0),
    .cfg_delay    (8'd0),
    .post_spikes  (postsyn_spikes),
    .post_vmem    (postsyn_vmem),
    .dbg_exc      (dbg_exc),
    .dbg_inh      (dbg_inh),
    .dbg_i_total  (dbg_i_total)
  );

  assign {n1_spike, n0_spike} = postsyn_spikes;
  assign n0_vmem = postsyn_vmem[0];
  assign n1_vmem = postsyn_vmem[1];
  assign n0_i_total = dbg_i_total[0];
  assign n1_i_total = dbg_i_total[1];
  assign n0_g_exc   = dbg_exc[0];
  assign n1_g_exc   = dbg_exc[1];
  assign n0_g_inh   = dbg_inh[0];
  assign n1_g_inh   = dbg_inh[1];

endmodule
