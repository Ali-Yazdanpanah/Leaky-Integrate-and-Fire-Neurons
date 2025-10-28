set script_dir [file dirname [info script]]
set root_dir   [file normalize "$script_dir/.."]
cd $root_dir

set inc_opt "+incdir+rtl"
set sources {
  rtl/lif_pkg.vh
  rtl/lif_neuron.v
  tb/tb_accuracy_lif.sv
}

if {[file exists xsim.dir]} {
  file delete -force xsim.dir
}
foreach artifact {xelab.pb xelab.log xvlog.log xsim.log accuracy_metrics.csv accuracy_sim.wdb accuracy_sim.tcl} {
  if {[file exists $artifact]} {
    file delete -force $artifact
  }
}

puts "INFO: Compiling tb_accuracy_lif sources..."
set compile_cmd [list xvlog -sv "+incdir+rtl" rtl/lfsr16.v rtl/lif_neuron.v tb/tb_accuracy_lif.sv]
if {[catch {exec {*}$compile_cmd} result]} {
  puts stderr $result
  exit 1
}

puts "INFO: Elaborating tb_accuracy_lif..."
set elaborate_cmd [list xelab tb_accuracy_lif -debug typical -s accuracy_sim]
if {[catch {exec {*}$elaborate_cmd} result]} {
  puts stderr $result
  exit 1
}

puts "INFO: Running accuracy bench simulation..."
set sim_cmd [list xsim accuracy_sim --runall]
if {[catch {exec {*}$sim_cmd} result]} {
  puts stderr $result
  exit 1
}

puts "INFO: Accuracy bench complete. Check scripts/accuracy_metrics.csv (or local directory)."
exit 0
