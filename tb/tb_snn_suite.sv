`timescale 1ns/1ps
`include "../rtl/lif_pkg.vh"

module tb_snn_suite;
  localparam CLK_HALF = 5; // 100 MHz
  localparam real CLK_PERIOD_NS = 2.0 * CLK_HALF;

  reg clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  reg rstn = 1'b0;
  reg in0_spk = 1'b0;
  reg in1_spk = 1'b0;

  wire n0_spk, n1_spk;
  wire signed [`W-1:0] n0_v, n1_v;
  wire signed [`W-1:0] n0_i, n1_i;
  wire signed [`W-1:0] n0_g_exc, n1_g_exc;
  wire signed [`W-1:0] n0_g_inh, n1_g_inh;

  real sim_time_ns;

  snn_simple #(
    .REFR_TICKS(4),
    .G_DECAY_E(`FX(0.92)),
    .G_DECAY_I(`FX(0.88))
  ) DUT (
    .clk(clk),
    .rst_n(rstn),
    .in0_spike(in0_spk),
    .in1_spike(in1_spk),
    .n0_spike(n0_spk),
    .n1_spike(n1_spk),
    .n0_vmem(n0_v),
    .n1_vmem(n1_v),
    .n0_i_total(n0_i),
    .n1_i_total(n1_i),
    .n0_g_exc(n0_g_exc),
    .n1_g_exc(n1_g_exc),
    .n0_g_inh(n0_g_inh),
    .n1_g_inh(n1_g_inh)
  );

  integer cycle_ctr = 0;
  integer scene_cycle = 0;
  string curr_scene = "reset";
  integer csv_fd;

  function real fx_to_real(input signed [`W-1:0] val);
    fx_to_real = val / (1.0 * (1 << `Q));
  endfunction

  task automatic set_scene(input string name);
    begin
      curr_scene  = name;
      scene_cycle = 0;
    end
  endtask

  task automatic run_step_current;
    input int duration;
    input int period;
    begin
      set_scene("step_drive");
      for (int i = 0; i < duration; i++) begin
        in0_spk = (i >= period);
        in1_spk = 1'b0;
        @(posedge clk);
        scene_cycle++;
      end
      in0_spk = 1'b0;
      in1_spk = 1'b0;
    end
  endtask

  task automatic run_burst;
    input int duration;
    input int burst_period;
    input int burst_len;
    begin
      set_scene("burst_train");
      for (int i = 0; i < duration; i++) begin
        if (((i % burst_period) < burst_len))
          in0_spk = 1'b1;
        else
          in0_spk = 1'b0;
        in1_spk = ((i % (burst_period/2)) == 0);
        @(posedge clk);
        scene_cycle++;
      end
      in0_spk = 1'b0;
      in1_spk = 1'b0;
    end
  endtask

  task automatic run_random;
    input int duration;
    input int seed;
    begin
      int local_seed = seed;
      set_scene("constrained_random");
      for (int i = 0; i < duration; i++) begin
        local_seed = (1103515245 * local_seed + 12345);
        in0_spk = (local_seed[15:0] < 16'd3000);
        local_seed = (1103515245 * local_seed + 6789);
        in1_spk = (local_seed[15:0] < 16'd5000);
        @(posedge clk);
        scene_cycle++;
      end
      in0_spk = 1'b0;
      in1_spk = 1'b0;
    end
  endtask

  task automatic run_idle;
    input string label;
    input int cycles;
    begin
      set_scene(label);
      in0_spk = 1'b0;
      in1_spk = 1'b0;
      for (int i = 0; i < cycles; i++) begin
        @(posedge clk);
        scene_cycle++;
      end
    end
  endtask

  always @(posedge clk) begin
    if (!rstn) begin
      cycle_ctr  <= 0;
    end else begin
      cycle_ctr  <= cycle_ctr + 1;
      if (csv_fd) begin
        real t_ns;
        t_ns = cycle_ctr * CLK_PERIOD_NS;
        $fwrite(csv_fd,
                "%0d,%0f,%s,%0d,%0d,%0d,%0d,%f,%f,%f,%f,%f,%f\n",
                cycle_ctr,
                t_ns,
                curr_scene,
                in0_spk,
                in1_spk,
                n0_spk,
                n1_spk,
                fx_to_real(n0_v),
                fx_to_real(n1_v),
                fx_to_real(n0_i),
                fx_to_real(n1_i),
                fx_to_real(n0_g_exc),
                fx_to_real(n1_g_exc));
      end
    end

    sim_time_ns = cycle_ctr * CLK_PERIOD_NS;
    if (rstn && (n0_spk || n1_spk)) begin
      $display("[%0t ns][%s] spike: n0=%0d n1=%0d v0=%0f v1=%0f",
               sim_time_ns,
               curr_scene,
               n0_spk,
               n1_spk,
               fx_to_real(n0_v),
               fx_to_real(n1_v));
    end
  end

  initial begin
    $dumpfile("snn_suite.vcd");
    $dumpvars(0, tb_snn_suite);

    repeat (10) @(posedge clk);
    rstn = 1'b1;

    csv_fd = $fopen("snn_suite_trace.csv", "w");
    if (csv_fd == 0) begin
      $fatal(1, "Failed to open snn_suite_trace.csv");
    end
    $fdisplay(csv_fd,
              "cycle,time_ns,scene,in0_spk,in1_spk,n0_spk,n1_spk,n0_v_real,n1_v_real,n0_i_real,n1_i_real,n0_g_exc_real,n1_g_exc_real");

    run_step_current(400, 10);
    run_idle("idle_gap", 20);

    run_burst(400, 40, 4);
    run_idle("idle_gap", 20);

    run_random(800, 32'h1234_5678);

    run_idle("idle_gap", 20);

    $display("Suite complete.");
    if (csv_fd) $fclose(csv_fd);
    $finish;
  end
endmodule
