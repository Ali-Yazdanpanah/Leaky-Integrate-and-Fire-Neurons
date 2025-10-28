`timescale 1ns/1ps
`include "lif_pkg.vh"

module lif_neuron #(
  parameter signed [`W-1:0] V_TH    = `FX(1.0),
  parameter signed [`W-1:0] V_RESET = `FX(0.0),
  parameter signed [`W-1:0] V_REST  = `FX(0.0),
  parameter signed [`W-1:0] LEAK_A  = `FX(0.96),  // leak multiplier applied to (v_mem - V_REST)
  parameter integer          REFR_TICKS = 0       // refractory duration in cycles
)(
  input  wire                   clk,
  input  wire                   rst_n,    // active-low
  input  wire signed [`W-1:0]   i_in,     // input current (Q4.12)
  output reg                    spike,
  output reg  signed [`W-1:0]   v_mem
);
  wire signed [`W-1:0]   v_delta   = v_mem - V_REST;
  wire signed [2*`W-1:0] mult_full = $signed(LEAK_A) * $signed(v_delta);
  wire signed [`W-1:0]   leak_term = V_REST + (mult_full >>> `Q);
  wire signed [`W:0]     v_next_full = $signed(leak_term) + $signed(i_in);

  function integer clog2;
    input integer value;
    integer i;
    begin
      clog2 = 0;
      for (i = value - 1; i > 0; i = i >> 1)
        clog2 = clog2 + 1;
    end
  endfunction

  localparam integer REFR_WIDTH = (REFR_TICKS > 0) ? clog2(REFR_TICKS + 1) : 1;
  reg [REFR_WIDTH-1:0] refr_ctr;

  localparam signed [`W-1:0] FX_MAX = `FX_MAX;
  localparam signed [`W-1:0] FX_MIN = `FX_MIN;

  function automatic signed [`W-1:0] sat_fx;
    input signed [`W:0] value;
    begin
      if (value > FX_MAX)
        sat_fx = FX_MAX;
      else if (value < FX_MIN)
        sat_fx = FX_MIN;
      else
        sat_fx = value[`W-1:0];
    end
  endfunction

  wire signed [`W-1:0] v_next_sat = sat_fx(v_next_full);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      v_mem <= V_RESET;
      spike <= 1'b0;
      refr_ctr <= {REFR_WIDTH{1'b0}};
    end else begin
      if (refr_ctr != {REFR_WIDTH{1'b0}}) begin
        refr_ctr <= refr_ctr - {{(REFR_WIDTH-1){1'b0}}, 1'b1};
        v_mem <= V_RESET;
        spike <= 1'b0;
      end else begin
        if (v_next_sat >= V_TH) begin
          v_mem <= V_RESET;
          spike <= 1'b1;     // one-cycle pulse
          if (REFR_TICKS > 0)
            refr_ctr <= REFR_TICKS[REFR_WIDTH-1:0];
        end else begin
          v_mem <= v_next_sat;
          spike <= 1'b0;
        end
      end
    end
  end
endmodule
