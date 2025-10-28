`timescale 1ns/1ps
module lfsr16(
  input  wire clk,
  input  wire rst_n,
  output reg [15:0] rnd
);
`ifndef LFSR_SEED
`define LFSR_SEED 16'hACE1
`endif

  wire fb = rnd[15] ^ rnd[13] ^ rnd[12] ^ rnd[10]; // taps: 16,14,13,11
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) rnd <= `LFSR_SEED;
    else       rnd <= {rnd[14:0], fb};
  end
endmodule
