RTL_FILES = ../rtl/s_axil_wr.sv ../rtl/s_axil_rd.sv ../rtl/s_axil_top.sv

TB_FILES =  ./tb/axil_tb_top.sv ./tb/axil_if.sv

all: clean compile sim cov

# -kdb -debug_access+all
compile:
	mkdir -p logs
	vcs -ntb_opts uvm-1.2 -sverilog -full64 \
		-cm line+cond+fsm+branch+tgl -timescale=1ns/1ps \
		+incdir+../rtl+./tb $(RTL_FILES) $(TB_FILES) -l logs/comp.log

sim:
	./simv -cm line+cond+fsm+branch+tgl -l logs/simv.log

waveform:
	verdi -ssf novas.fsdb

cov:
	urg -dir simv.vdb -show text -report urg_report
	@echo "HTML coverage report: urg_report/dashboard.html"

clean:
	rm -rf AN.DB csrc simv* ucli.key novas* logs work* verdi* urgReport urg_report .fsm.sch.verilog.xml cm.log vc_hdrs.h tr_db.log
