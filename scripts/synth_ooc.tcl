set script_dir [file dirname [info script]]
set root_dir   [file normalize "$script_dir/.."]
cd $root_dir

set part_name "xc7a35tcpg236-1"
set top_name  "snn_simple"

file mkdir reports
file mkdir logs

puts "INFO: Launching out-of-context synthesis for $top_name on $part_name"

set_property include_dirs [list rtl] [current_fileset]

read_verilog -sv rtl/lfsr16.v
read_verilog -sv rtl/poisson_spike_gen.v
read_verilog -sv rtl/lif_neuron.v
read_verilog -sv rtl/snn_layer.sv
read_verilog -sv rtl/snn_simple.sv

set_param synth.elaboration.rodinMoreOptions "rt::set_parameter compile_time_elaboration 1"

synth_design -top $top_name -part $part_name -mode out_of_context

report_utilization      -file reports/${top_name}_utilization.rpt
report_timing_summary   -file reports/${top_name}_timing.rpt

write_checkpoint -force ${top_name}_synth.dcp

puts "INFO: OOC synthesis finished. Reports written to reports/."
exit 0
