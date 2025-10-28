VIVADO ?= vivado
PYTHON ?= python3
SEED   ?= 16'hACE1
FAN_IN ?= 8

.PHONY: sim synth_ooc figures clean

sim:
	@echo "==> Running behavioral simulation (seed $(SEED))"
	@mkdir -p logs scripts
	@LFSR_SEED=$(SEED) $(VIVADO) -mode batch -source scripts/sim_suite.tcl > logs/sim_suite.log 2>&1 || (cat logs/sim_suite.log && exit 1)
	@mkdir -p scripts
	@if [ -f snn_suite_trace.csv ]; then cp snn_suite_trace.csv scripts/; fi
	@echo "==> Simulation trace: scripts/snn_suite_trace.csv"

synth_ooc:
	@echo "==> Launching out-of-context synthesis"
	@mkdir -p logs reports
	@$(VIVADO) -mode batch -source scripts/synth_ooc.tcl > logs/synth_ooc.log 2>&1 || (cat logs/synth_ooc.log && exit 1)
	@echo "==> Reports in reports/snn_simple_utilization.rpt and reports/snn_simple_timing.rpt"

figures:
	@echo "==> Regenerating figures"
	@$(PYTHON) scripts/plot_lif_neuron.py
	@$(PYTHON) scripts/plot_snn_simple.py
	@$(PYTHON) scripts/plot_snn_suite.py

clean:
	@rm -rf xsim.dir snn_suite_sim.wdb snn_suite_sim.tcl *.jou *.log *.pb *.dcp
	@rm -f snn_suite_trace.csv
	@echo "==> Cleaned build artefacts"
