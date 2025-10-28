`timescale 1ns/1ps
module poisson_spike_gen #(
  parameter [15:0] RATE = 16'd3277   // ≈0.05 per tick (5%)
)(
  input  wire clk,
  input  wire rst_n,
  output reg  spike
);
  wire [15:0] r;
  lfsr16 u_rng(.clk(clk), .rst_n(rst_n), .rnd(r));
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) spike <= 1'b0;
    else       spike <= (r < RATE);  // 1-cycle spike with prob RATE/65536
  end
endmodule
