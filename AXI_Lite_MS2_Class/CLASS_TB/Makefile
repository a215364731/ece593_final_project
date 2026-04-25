RTL_FILES = ../rtl/s_axil_wr.sv ../rtl/s_axil_rd.sv ../rtl/s_axil_top.sv

TB_FILES =  ./tb/testbench_top.sv ./tb/axil_if.sv \
		   	./tb/env.sv ./tb/tests.sv \
			./tb/driver.sv ./tb/generator.sv ./tb/monitor.sv ./tb/transaction.sv

TOP = testbench_top

all: clean compile sim cov

compile:
	mkdir -p logs
	vlogan -sverilog +incdir+../rtl -kdb $(RTL_FILES) $(TB_FILES) +incdir+./tb -l logs/vlogan.log
	vcs -sverilog -full64 -kdb -debug_access+all -cm line+cond+fsm+branch+tgl $(TOP) -l logs/comp.log
sim:
	./simv -cm line+cond+fsm+branch+tgl -l logs/simv.log

waveform:
	verdi -ssf novas.fsdb

cov:
	urg -dir simv.vdb -show text

clean:
	rm -rf AN.DB csrc simv* ucli.key novas* logs work* verdi* urgReport .fsm.sch.verilog.xml cm.log

