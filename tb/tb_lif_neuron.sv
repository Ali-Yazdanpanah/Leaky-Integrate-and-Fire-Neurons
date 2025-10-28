`timescale 1ns/1ps
`include "../rtl/lif_pkg.vh"

module tb_lif_neuron;
  localparam int CLK_HALF = 5;  // 100 MHz clock

  reg clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  reg                    rst_n = 1'b0;
  logic signed [`W-1:0]  i_in;
  wire                   spike;
  wire signed [`W-1:0]   v_mem;

  localparam signed [`W-1:0] V_TH_P      = `FX(1.0);
  localparam signed [`W-1:0] V_RESET_P   = `FX(0.0);
  localparam signed [`W-1:0] V_REST_P    = `FX(0.0);
  localparam signed [`W-1:0] LEAK_P      = `FX(0.96);
  localparam int              REFR_TICKS = 3;

  lif_neuron #(
    .V_TH       (V_TH_P),
    .V_RESET    (V_RESET_P),
    .V_REST     (V_REST_P),
    .LEAK_A     (LEAK_P),
    .REFR_TICKS (REFR_TICKS)
  ) dut (
    .clk   (clk),
    .rst_n (rst_n),
    .i_in  (i_in),
    .spike (spike),
    .v_mem (v_mem)
  );

  localparam signed [`W-1:0] FX_MAX = `FX_MAX;
  localparam signed [`W-1:0] FX_MIN = `FX_MIN;

  function automatic int clog2_int(input int value);
    int i;
    begin
      if (value <= 1) return 1;
      for (i = 0; (1 << i) < value; i++);
      return i;
    end
  endfunction

  localparam int REFR_WIDTH = (REFR_TICKS > 0) ? clog2_int(REFR_TICKS + 1) : 1;

  logic signed [`W-1:0] exp_vmem_state;
  logic [REFR_WIDTH-1:0] exp_refr_state;
  logic signed [`W-1:0] exp_vmem_d;
  logic exp_spike_d;

  function automatic signed [`W-1:0] sat_fx(input signed [`W:0] value);
    if (value > FX_MAX)      sat_fx = FX_MAX;
    else if (value < FX_MIN) sat_fx = FX_MIN;
    else                     sat_fx = value[`W-1:0];
  endfunction

  localparam signed [`W-1:0] I_BASELINE = `FX(0.0);
  localparam signed [`W-1:0] I_EXC      = `FX(0.35);
  localparam signed [`W-1:0] I_INH      = `FX(0.25);

  localparam int EXC_RATE  = 16'd4096;  // ~6.25% chance per tick
  localparam int INH_RATE  = 16'd2048;  // ~3.1% chance per tick
  localparam int SIM_CYCLES = 5000;

  logic exc_spike;
  logic inh_spike;

  poisson_spike_gen #(.RATE(EXC_RATE)) u_exc (
    .clk  (clk),
    .rst_n(rst_n),
    .spike(exc_spike)
  );

  poisson_spike_gen #(.RATE(INH_RATE)) u_inh (
    .clk  (clk),
    .rst_n(rst_n),
    .spike(inh_spike)
  );

  always_comb begin
    logic signed [`W:0] curr_accum;
    curr_accum = {{1{I_BASELINE[`W-1]}}, I_BASELINE};
    if (exc_spike)
      curr_accum += {{1{I_EXC[`W-1]}}, I_EXC};
    if (inh_spike)
      curr_accum -= {{1{I_INH[`W-1]}}, I_INH};
    i_in = sat_fx(curr_accum);
  end

  function real fx_to_real(input signed [`W-1:0] val);
    fx_to_real = val / (1.0 * (1 << `Q));
  endfunction

  int spike_count;
  int total_cycles;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      spike_count <= 0;
    else if (spike)
      spike_count <= spike_count + 1;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      exp_vmem_state <= V_RESET_P;
      exp_refr_state <= '0;
      exp_vmem_d     <= V_RESET_P;
      exp_spike_d    <= 1'b0;
    end else begin
      logic signed [`W-1:0] next_vmem;
      logic next_spike;
      logic [REFR_WIDTH-1:0] next_refr;

      if (exp_refr_state != '0) begin
        next_refr = exp_refr_state - {{(REFR_WIDTH-1){1'b0}}, 1'b1};
        next_vmem = V_RESET_P;
        next_spike = 1'b0;
      end else begin
        logic signed [`W-1:0]   v_delta;
        logic signed [(2*`W)-1:0] mult_full;
        logic signed [`W-1:0]   leak_term;
        logic signed [`W:0]     v_next_full;
        logic signed [`W-1:0]   v_next_sat;

        v_delta    = exp_vmem_state - V_REST_P;
        mult_full  = $signed(LEAK_P) * $signed(v_delta);
        leak_term  = V_REST_P + (mult_full >>> `Q);
        v_next_full = $signed(leak_term) + $signed(i_in);
        v_next_sat  = sat_fx(v_next_full);

        if (v_next_sat >= V_TH_P) begin
          next_vmem  = V_RESET_P;
          next_spike = 1'b1;
          next_refr  = (REFR_TICKS > 0) ? REFR_TICKS[REFR_WIDTH-1:0] : '0;
        end else begin
          next_vmem  = v_next_sat;
          next_spike = 1'b0;
          next_refr  = '0;
        end
      end

      exp_vmem_d     <= next_vmem;
      exp_spike_d    <= next_spike;
      exp_vmem_state <= next_vmem;
      exp_refr_state <= next_refr;
    end
  end

  always @(negedge clk) begin
    if (rst_n) begin
      if (v_mem !== exp_vmem_d) begin
        $error("[%0t] v_mem mismatch: expected %0d (%.3f) got %0d (%.3f)",
               $time, exp_vmem_d, fx_to_real(exp_vmem_d), v_mem, fx_to_real(v_mem));
      end
      if (spike !== exp_spike_d) begin
        $error("[%0t] spike mismatch: expected %0b got %0b", $time, exp_spike_d, spike);
      end
    end
  end

  bit auto_finish;
  initial begin
    auto_finish = $test$plusargs("AUTO_FINISH");
  end

  initial begin
    $dumpfile("lif_neuron.vcd");
    $dumpvars(0, tb_lif_neuron);

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    total_cycles = 0;
    while (total_cycles < SIM_CYCLES) begin
      @(posedge clk);
      total_cycles++;
    end

    $display("[%0t] lif_neuron single-neuron suite completed. Total spikes=%0d",
             $time, spike_count);
    $finish;
  end
endmodule
