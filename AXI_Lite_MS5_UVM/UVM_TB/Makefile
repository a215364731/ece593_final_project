RTL_FILES = ../rtl/s_axil_wr.sv ../rtl/s_axil_rd.sv ../rtl/s_axil_top.sv

TB_FILES =  ./tb/axil_tb_top.sv ./tb/axil_if.sv

all: clean compile sim cov

SEED = 1
NUM_SEEDS = 50

# -kdb -debug_access+all
compile:
	mkdir -p logs
	vcs -ntb_opts uvm-1.2 -sverilog -full64 \
		-cm line+cond+fsm+branch+tgl -timescale=1ns/1ps \
		+incdir+../rtl+./tb $(RTL_FILES) $(TB_FILES) -l logs/comp.log

sim:
	./simv -cm line+cond+fsm+branch+tgl +ntb_random_seed=$(SEED) -l logs/simv.log

regress:
	mkdir -p logs
	rm -f logs/regress_summary.log
	@pass=0; fail=0; \
	for s in `seq 1 $(NUM_SEEDS)`; do \
		echo "[MAKE] Running seed=$$s"; \
		./simv $(SIM_FLAGS) +ntb_random_seed=$$s -cm_name seed_$$s -l logs/sim_seed_$$s.log > /dev/null 2>&1; \
		if grep -q "UVM_ERROR :    0" logs/sim_seed_$$s.log && grep -q "UVM_FATAL :    0" logs/sim_seed_$$s.log; then \
			pass=$$((pass+1)); echo "seed=$$s PASS" >> logs/regress_summary.log; \
		else \
			fail=$$((fail+1)); echo "seed=$$s FAIL" >> logs/regress_summary.log; \
		fi; \
	done; \
	echo "========================================"; \
	echo " Regression complete: $$pass pass, $$fail fail"; \
	echo " Summary: logs/regress_summary.log"; \
	echo "========================================"

waveform:
	verdi -ssf novas.fsdb

cov:
	urg -dir simv.vdb -show text -report urg_report
	@echo "HTML coverage report: urg_report/dashboard.html"

clean:
	rm -rf AN.DB csrc simv* ucli.key novas* logs work* verdi* urgReport urg_report .fsm.sch.verilog.xml cm.log vc_hdrs.h tr_db.log
