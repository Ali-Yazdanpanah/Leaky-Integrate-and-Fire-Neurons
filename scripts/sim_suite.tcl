set script_dir [file dirname [info script]]
set root_dir   [file normalize "$script_dir/.."]
cd $root_dir

set inc_opt "+incdir+rtl"
set sources {
  rtl/lfsr16.v
  rtl/poisson_spike_gen.v
  rtl/lif_neuron.v
  rtl/snn_layer.sv
  rtl/snn_simple.sv
  tb/tb_snn_suite.sv
}

if {[file exists xsim.dir]} {
  file delete -force xsim.dir
}
foreach artifact {xelab.pb xelab.log xvlog.log xsim.log snn_suite_sim.wdb snn_suite_sim.tcl} {
  if {[file exists $artifact]} {
    file delete -force $artifact
  }
}

set seed [expr {[info exists ::env(LFSR_SEED)] ? $::env(LFSR_SEED) : "16'hACE1"}]

set compile_cmd [list xvlog -sv $inc_opt "+define+LFSR_SEED=$seed"]
foreach src $sources {
  lappend compile_cmd $src
}
puts "INFO: Compiling RTL and testbench..."
if {[catch {exec {*}$compile_cmd} result]} {
  puts stderr $result
  exit 1
}

set elaborate_cmd [list xelab tb_snn_suite -debug typical -s snn_suite_sim]
puts "INFO: Elaborating top tb_snn_suite..."
if {[catch {exec {*}$elaborate_cmd} result]} {
  puts stderr $result
  exit 1
}

set sim_cmd [list xsim snn_suite_sim --runall]
puts "INFO: Running simulation..."
if {[catch {exec {*}$sim_cmd} result]} {
  puts stderr $result
  exit 1
}

puts "INFO: Simulation complete. CSV trace should be present at snn_suite_trace.csv."
exit 0
