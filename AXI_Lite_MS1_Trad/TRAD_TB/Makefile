RTL_FILES = ./testbench.sv ../rtl/s_axil_wr.sv ../rtl/s_axil_rd.sv ../rtl/s_axil_top.sv

all: clean compile sim

compile:
	mkdir -p logs
	vlogan -sverilog +incdir+../rtl -kdb $(RTL_FILES) -l logs/vlogan.log
	vcs -sverilog -full64 -kdb -debug_access+all testbench -l logs/comp.log
sim:
	./simv -l logs/simv.log

waveform:
	verdi -ssf novas.fsdb

clean:
	rm -rf AN.DB csrc simv* ucli.key novas* logs work* verdi*

clean_for_submit:
	rm -rf AN.DB csrc simv* ucli.key novas* work* verdi*
