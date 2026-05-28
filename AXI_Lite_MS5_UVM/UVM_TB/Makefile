# =============================================================================
# Makefile - AXI4-Lite UVM Testbench (MS5)
#
# Targets:
#   make compile       Compile RTL + TB with coverage instrumentation
#   make sim           Run one simulation (single seed)
#   make sim SEED=42   Run one simulation with specific seed
#   make sim TEST=name Run a specific UVM test (default: axil_test)
#   make regress       Run SEEDS-seed regression sequentially (default 50)
#   make merge         Merge coverage DBs from all regression seeds
#   make cov           Generate URG HTML coverage report
#   make all           clean + compile + regress + merge + cov
#   make waveform      Launch Verdi on the FSDB waveform
#   make clean         Remove all build artifacts
#   make help          Show this help
#
# Variables (override on command line):
#   SEEDS    Number of regression seeds            (default 50)
#   SEED     Seed for a single 'make sim'          (default 1)
#   TEST     UVM test name                         (default axil_test)
#   VERB     UVM verbosity (UVM_LOW/MEDIUM/HIGH)   (default UVM_MEDIUM)
# =============================================================================

# -----------------------------------------------------------------------------
# Source files
# -----------------------------------------------------------------------------
RTL_FILES = ../rtl/s_axil_wr.sv \
            ../rtl/s_axil_rd.sv \
            ../rtl/s_axil_top.sv

TB_FILES  = ./tb/axil_tb_top.sv \
            ./tb/axil_if.sv

# -----------------------------------------------------------------------------
# Tunables (override on command line, e.g. 'make regress SEEDS=10')
# -----------------------------------------------------------------------------
SEEDS ?= 50
SEED  ?= 1
TEST  ?= axil_test
VERB  ?= UVM_MEDIUM

# -----------------------------------------------------------------------------
# Coverage configuration
# -----------------------------------------------------------------------------
CM_METRICS = line+cond+fsm+branch+tgl
CM_HIER    = cm_hier.cfg
COV_DIR    = simv.vdb
MERGED_DIR = merged.vdb

# -----------------------------------------------------------------------------
# VCS flags
# -----------------------------------------------------------------------------
VCS_FLAGS = -ntb_opts uvm-1.2 -sverilog -full64 \
            -timescale=1ns/1ps \
            +incdir+../rtl+./tb \
            -cm $(CM_METRICS) \
            -cm_hier $(CM_HIER) \
            -cm_dir $(COV_DIR)

SIM_FLAGS = -cm $(CM_METRICS) \
            -cm_dir $(COV_DIR) \
            +UVM_TESTNAME=$(TEST) \
            +UVM_VERBOSITY=$(VERB)

# -----------------------------------------------------------------------------
# Default target
# -----------------------------------------------------------------------------
.PHONY: all
all: clean compile regress merge cov

# -----------------------------------------------------------------------------
# Compile
# -----------------------------------------------------------------------------
.PHONY: compile
compile:
	@mkdir -p logs
	@echo "[MAKE] Compiling with coverage scope '$(CM_HIER)'..."
	vcs $(VCS_FLAGS) $(RTL_FILES) $(TB_FILES) -l logs/comp.log
	@echo "[MAKE] Compile complete."

# -----------------------------------------------------------------------------
# Single simulation run
#   Coverage DB named by seed so it doesn't overwrite previous runs.
# -----------------------------------------------------------------------------
.PHONY: sim
sim:
	@mkdir -p logs
	@echo "[MAKE] Running seed=$(SEED) test=$(TEST)..."
	./simv $(SIM_FLAGS) \
	    -cm_name seed_$(SEED) \
	    +ntb_random_seed=$(SEED) \
	    -l logs/sim_seed_$(SEED).log
	@echo "[MAKE] Run complete: logs/sim_seed_$(SEED).log"

# -----------------------------------------------------------------------------
# Regression: SEEDS sequential simulations
# -----------------------------------------------------------------------------
.PHONY: regress
regress:
	@mkdir -p logs
	@echo "[MAKE] Regression: $(SEEDS) seeds, test=$(TEST)"
	@rm -f logs/regress_summary.log
	@pass=0; fail=0; \
	for s in `seq 1 $(SEEDS)`; do \
	    echo "[MAKE]   seed=$$s"; \
	    ./simv $(SIM_FLAGS) \
	        -cm_name seed_$$s \
	        +ntb_random_seed=$$s \
	        -l logs/sim_seed_$$s.log > /dev/null 2>&1; \
	    if grep -q "UVM_ERROR :    0" logs/sim_seed_$$s.log && \
	       grep -q "UVM_FATAL :    0" logs/sim_seed_$$s.log; then \
	        pass=$$((pass+1)); \
	        echo "seed=$$s PASS" >> logs/regress_summary.log; \
	    else \
	        fail=$$((fail+1)); \
	        echo "seed=$$s FAIL" >> logs/regress_summary.log; \
	    fi; \
	done; \
	echo "[MAKE] Regression complete: $$pass pass, $$fail fail"; \
	echo "[MAKE] Summary: logs/regress_summary.log"

# -----------------------------------------------------------------------------
# Merge coverage databases from all regression seeds
# -----------------------------------------------------------------------------
.PHONY: merge
merge:
	@echo "[MAKE] Merging coverage databases into $(MERGED_DIR)..."
	@rm -rf $(MERGED_DIR)
	urg -dir $(COV_DIR) -dbname $(MERGED_DIR) -noreport
	@echo "[MAKE] Merge complete: $(MERGED_DIR)"

# -----------------------------------------------------------------------------
# Coverage closure: rebuild + run once with MEM_INIT="" to hit the
# else-branches on s_axil_top.sv:73,80 that the main build can't reach.
# Produces a separate coverage DB; merge_all combines it with the main DB.
# -----------------------------------------------------------------------------
COV_DIR_NO_INIT = simv_no_init.vdb

.PHONY: compile_no_init
compile_no_init:
	@mkdir -p logs
	@echo "[MAKE] Compiling with MEM_INIT_EMPTY (no memory init)..."
	vcs -ntb_opts uvm-1.2 -sverilog -full64 \
	    -timescale=1ns/1ps \
	    +incdir+../rtl+./tb \
	    +define+MEM_INIT_EMPTY \
	    -cm $(CM_METRICS) -cm_hier $(CM_HIER) -cm_dir $(COV_DIR_NO_INIT) \
	    -o simv_no_init -Mdir=csrc_no_init \
	    $(RTL_FILES) $(TB_FILES) -l logs/comp_no_init.log
	@echo "[MAKE] No-init compile complete: simv_no_init"

.PHONY: sim_no_init
sim_no_init:
	@mkdir -p logs
	@echo "[MAKE] Running no-init build (single seed)..."
	./simv_no_init -cm $(CM_METRICS) -cm_dir $(COV_DIR_NO_INIT) \
	    -cm_name no_init_seed_1 \
	    +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_NONE \
	    +ntb_random_seed=1 \
	    -l logs/sim_no_init.log
	@echo "[MAKE] No-init run complete."

.PHONY: merge_all
merge_all:
	@echo "[MAKE] Merging main + no-init coverage DBs into $(MERGED_DIR)..."
	@rm -rf $(MERGED_DIR)
	urg -dir $(COV_DIR) -dir $(COV_DIR_NO_INIT) -dbname $(MERGED_DIR) -noreport
	@echo "[MAKE] Merge complete: $(MERGED_DIR)"

# -----------------------------------------------------------------------------
# coverage_full ? one-command full coverage flow (final 96.73% result):
#   1. 50-seed regression (main build)
#   2. no-init build + 1 seed (closes MEM_INIT else-branches)
#   3. merge both coverage DBs
#   4. generate URG report
# This is the single command to reproduce the final coverage number.
# -----------------------------------------------------------------------------
.PHONY: coverage_full
coverage_full: clean compile regress compile_no_init sim_no_init merge_all cov
	@echo ""
	@echo "[MAKE] ===== FULL COVERAGE FLOW COMPLETE ====="
	@echo "[MAKE] Report: urg_report/dashboard.html (and dashboard.txt)"

# -----------------------------------------------------------------------------
# Bug injection (MS5 deliverable 5c)
#   make inject BUG=N     Apply bug N, recompile, run, capture, restore
#   make inject_all       Loop through all 6 bugs
#   make bugreport        Generate summary table from captured logs
# -----------------------------------------------------------------------------
BUGS_DIR = bugs
BUG     ?= 1

.PHONY: inject
inject:
	@if [ ! -f $(BUGS_DIR)/bug$(BUG)_*.sh ]; then \
	    echo "[INJECT] ERROR: bug$(BUG)_*.sh not found in $(BUGS_DIR)/"; exit 1; \
	fi
	@mkdir -p $(BUGS_DIR)/results logs
	@BUG_SCRIPT=`ls $(BUGS_DIR)/bug$(BUG)_*.sh | head -1`; \
	BUG_NAME=`basename $$BUG_SCRIPT .sh`; \
	echo "[INJECT] === $$BUG_NAME ==="; \
	echo "[INJECT] Backing up RTL + TB sources..."; \
	cp ../rtl/s_axil_wr.sv   ../rtl/s_axil_wr.sv.golden; \
	cp ../rtl/s_axil_rd.sv   ../rtl/s_axil_rd.sv.golden; \
	cp ../rtl/s_axil_top.sv  ../rtl/s_axil_top.sv.golden; \
	cp ./tb/axil_env.sv      ./tb/axil_env.sv.golden; \
	cp ./tb/axil_sequences.sv ./tb/axil_sequences.sv.golden; \
	echo "[INJECT] Applying bug..."; \
	bash $$BUG_SCRIPT; \
	echo "[INJECT] Diff of injected change:"; \
	{ diff ../rtl/s_axil_wr.sv.golden    ../rtl/s_axil_wr.sv; \
	  diff ../rtl/s_axil_rd.sv.golden    ../rtl/s_axil_rd.sv; \
	  diff ../rtl/s_axil_top.sv.golden   ../rtl/s_axil_top.sv; \
	  diff ./tb/axil_env.sv.golden       ./tb/axil_env.sv; \
	  diff ./tb/axil_sequences.sv.golden ./tb/axil_sequences.sv; } > $(BUGS_DIR)/results/$$BUG_NAME.diff 2>/dev/null || true; \
	cat $(BUGS_DIR)/results/$$BUG_NAME.diff; \
	echo "[INJECT] Recompiling..."; \
	rm -rf csrc simv simv.daidir $(COV_DIR); \
	vcs $(VCS_FLAGS) $(RTL_FILES) $(TB_FILES) -l logs/comp_$$BUG_NAME.log > /dev/null 2>&1 || \
	    { echo "[INJECT] COMPILE FAILED (interesting!) - log: logs/comp_$$BUG_NAME.log"; \
	      cp logs/comp_$$BUG_NAME.log $(BUGS_DIR)/results/$$BUG_NAME.log; \
	      mv ../rtl/s_axil_wr.sv.golden    ../rtl/s_axil_wr.sv; \
	      mv ../rtl/s_axil_rd.sv.golden    ../rtl/s_axil_rd.sv; \
	      mv ../rtl/s_axil_top.sv.golden   ../rtl/s_axil_top.sv; \
	      mv ./tb/axil_env.sv.golden       ./tb/axil_env.sv; \
	      mv ./tb/axil_sequences.sv.golden ./tb/axil_sequences.sv; \
	      exit 0; }; \
	echo "[INJECT] Running sim (60-sec timeout)..."; \
	timeout 60 ./simv $(SIM_FLAGS) -cm_name $$BUG_NAME +ntb_random_seed=1 \
	    +UVM_VERBOSITY=UVM_NONE -l $(BUGS_DIR)/results/$$BUG_NAME.log > /dev/null 2>&1; \
	RC=$$?; \
	if [ $$RC -eq 124 ]; then \
	    echo "[INJECT] SIM TIMED OUT (bug hangs the DUT)"; \
	    echo "TIMEOUT" >> $(BUGS_DIR)/results/$$BUG_NAME.log; \
	fi; \
	echo "[INJECT] Result:"; \
	if grep -q "UVM_FATAL :    0" $(BUGS_DIR)/results/$$BUG_NAME.log && \
	   grep -q "UVM_ERROR :    0" $(BUGS_DIR)/results/$$BUG_NAME.log; then \
	    echo "  *** MISSED *** bug not caught by env"; \
	else \
	    ERR_LINE=`grep -m1 "UVM_ERROR\|UVM_FATAL\|TIMEOUT" $(BUGS_DIR)/results/$$BUG_NAME.log | head -1`; \
	    echo "  CAUGHT: $$ERR_LINE"; \
	fi; \
	echo "[INJECT] Restoring golden sources..."; \
	mv ../rtl/s_axil_wr.sv.golden    ../rtl/s_axil_wr.sv; \
	mv ../rtl/s_axil_rd.sv.golden    ../rtl/s_axil_rd.sv; \
	mv ../rtl/s_axil_top.sv.golden   ../rtl/s_axil_top.sv; \
	mv ./tb/axil_env.sv.golden       ./tb/axil_env.sv; \
	mv ./tb/axil_sequences.sv.golden ./tb/axil_sequences.sv; \
	echo "[INJECT] Done. Log: $(BUGS_DIR)/results/$$BUG_NAME.log"

.PHONY: inject_all
inject_all:
	@for n in 1 2 3 4 5 6 7; do \
	    $(MAKE) inject BUG=$$n; \
	    echo ""; \
	done
	@$(MAKE) bugreport

.PHONY: bugreport
bugreport:
	@echo ""
	@echo "============================================================"
	@echo "Bug Injection Summary"
	@echo "============================================================"
	@printf "%-30s %-8s %s\n" "Bug" "Status" "First-fail signature"
	@printf "%-30s %-8s %s\n" "---" "------" "----------------------"
	@for log in $(BUGS_DIR)/results/bug*.log; do \
	    name=`basename $$log .log`; \
	    if grep -q "TIMEOUT" $$log; then \
	        printf "%-30s %-8s %s\n" "$$name" "CAUGHT" "(sim timeout)"; \
	    elif grep -q "UVM_FATAL :    0" $$log && grep -q "UVM_ERROR :    0" $$log; then \
	        printf "%-30s %-8s %s\n" "$$name" "MISSED" "(env did not catch)"; \
	    else \
	        sig=`grep -m1 "UVM_ERROR\|UVM_FATAL" $$log | head -1 | cut -c1-50`; \
	        printf "%-30s %-8s %s\n" "$$name" "CAUGHT" "$$sig"; \
	    fi; \
	done
	@echo "============================================================"

# -----------------------------------------------------------------------------
# Coverage report (HTML + text)
# -----------------------------------------------------------------------------
.PHONY: cov
cov:
	@echo "[MAKE] Generating URG report..."
	@if [ -d $(MERGED_DIR) ]; then \
	    urg -dir $(MERGED_DIR) -format both -report urg_report; \
	else \
	    urg -dir $(COV_DIR)   -format both -report urg_report; \
	fi
	@echo "[MAKE] HTML report: urg_report/dashboard.html"
	@echo "[MAKE] Text report: urg_report/dashboard.txt"

# -----------------------------------------------------------------------------
# Waveform (requires -kdb -debug_access+all on compile, see notes)
# -----------------------------------------------------------------------------
.PHONY: waveform
waveform:
	verdi -ssf novas.fsdb &

# -----------------------------------------------------------------------------
# Clean
# -----------------------------------------------------------------------------
.PHONY: clean
clean:
	rm -rf AN.DB csrc csrc_no_init simv* ucli.key novas* logs work* verdi* \
	       urgReport urg_report $(COV_DIR) $(COV_DIR_NO_INIT) $(MERGED_DIR) \
	       .fsm.sch.verilog.xml cm.log vc_hdrs.h tr_db.log \
	       *.vdb ../rtl/*.golden tb/*.golden bugs/results

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
.PHONY: help
help:
	@echo ""
	@echo "AXI4-Lite UVM TB - Makefile targets"
	@echo "-----------------------------------"
	@echo "  make compile             Compile RTL + TB with coverage"
	@echo "  make sim                 Run one simulation (SEED=1, default)"
	@echo "  make sim SEED=42         Run with specific seed"
	@echo "  make sim TEST=name       Run a specific UVM test"
	@echo "  make regress             Run SEEDS-seed regression (default 50)"
	@echo "  make regress SEEDS=10    Smoke-test with 10 seeds"
	@echo "  make merge               Merge coverage DBs across seeds"
	@echo "  make cov                 Generate URG HTML/text report"
	@echo "  make all                 clean + compile + regress + merge + cov"
	@echo ""
	@echo "Coverage closure (MEM_INIT=\"\" extra build):"
	@echo "  make compile_no_init     Compile with +define+MEM_INIT_EMPTY"
	@echo "  make sim_no_init         Run no-init build, single seed"
	@echo "  make merge_all           Merge main + no-init DBs"
	@echo ""
	@echo "Bug injection (5c):"
	@echo "  make inject BUG=N        Apply, run, restore bug N (1..6)"
	@echo "  make inject_all          Run all 6 bugs sequentially"
	@echo "  make bugreport           Print summary table from results/"
	@echo ""
	@echo "Other:"
	@echo "  make waveform            Open Verdi (needs novas.fsdb)"
	@echo "  make clean               Remove all build artifacts"
	@echo ""
