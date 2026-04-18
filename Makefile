
# ==========================================================
# Project-centric Makefile with doc + rtl per milestone
# Includes help target
# For ECE593 Class Final Project
# Author: Venkatesh Patil (v.p@pdx.edu)
# Usage:
#   make help
#   make PROJECT=myproj
#   make MS4 PROJECT=async_fifo
# ==========================================================

PROJECT ?= AXI_Lite

.PHONY: all FINAL MS1 MS2 MS3 MS4 MS5 clean help

# Default target
all: FINAL MS1 MS2 MS3 MS4 MS5

# ---------------- HELP ----------------
help:
	@echo "=================================================="
	@echo " Milestone Project Makefile Help"
	@echo "=================================================="
	@echo ""
	@echo "Usage:"
	@echo "  make <target> PROJECT=<project_name>"
	@echo ""
	@echo "Common targets:"
	@echo "  help        : Show this help message"
	@echo "  all         : Create ALL milestone directories"
	@echo "  clean       : Remove ALL directories for project"
	@echo ""
	@echo "Milestone targets:"
	@echo "  MS1         : Create <project>_MS1_Trad  (Traditional TB)"
	@echo "  MS2         : Create <project>_MS2_Class (Class-based TB)"
	@echo "  MS3         : Create <project>_MS3_Class (Class-based TB)"
	@echo "  MS4         : Create <project>_MS4_UVM   (UVM TB)"
	@echo "  MS5         : Create <project>_MS5_UVM   (UVM TB)"
	@echo "  FINAL       : Create <project>_FINAL submission dirs"
	@echo ""
	@echo "Each milestone includes:"
	@echo "  - doc/   : Documentation"
	@echo "  - rtl/   : Design sources"
	@echo "  - TB dir : TRAD_TB / CLASS_TB / UVM_TB"
	@echo ""
	@echo "Examples:"
	@echo "  make help"
	@echo "  make PROJECT=fifo_uvm"
	@echo "  make MS4 PROJECT=arbiter"
	@echo "  make clean PROJECT=fifo_uvm"
	@echo ""

# ---------------- FINAL ----------------
FINAL:
	@echo "Creating FINAL structure..."
	@mkdir -p \
		$(PROJECT)_FINAL/M1 \
		$(PROJECT)_FINAL/M2 \
		$(PROJECT)_FINAL/M3 \
		$(PROJECT)_FINAL/M4 \
		$(PROJECT)_FINAL/M5
	@echo "# FINAL Submission\n\nProject: $(PROJECT)" > $(PROJECT)_FINAL/README.md

# ---------------- MS1 (Traditional TB) ----------------
MS1:
	@echo "Creating $(PROJECT)_MS1_Trad..."
	@mkdir -p \
		$(PROJECT)_MS1_Trad/doc \
		$(PROJECT)_MS1_Trad/rtl \
		$(PROJECT)_MS1_Trad/TRAD_TB
	@echo "# $(PROJECT) ? MS1 (Traditional TB)" > $(PROJECT)_MS1_Trad/doc/README.md
	@echo "# RTL Sources\n\nDesign files for MS1." > $(PROJECT)_MS1_Trad/rtl/README.md
	@echo "# Traditional Testbench\n\nMilestone 1" > $(PROJECT)_MS1_Trad/TRAD_TB/README.md

# ---------------- MS2 (Class TB) ----------------
MS2:
	@echo "Creating $(PROJECT)_MS2_Class..."
	@mkdir -p \
		$(PROJECT)_MS2_Class/doc \
		$(PROJECT)_MS2_Class/rtl \
		$(PROJECT)_MS2_Class/CLASS_TB
	@echo "# $(PROJECT) ? MS2 (Class-based TB)" > $(PROJECT)_MS2_Class/doc/README.md
	@echo "# RTL Sources\n\nDesign files for MS2." > $(PROJECT)_MS2_Class/rtl/README.md
	@echo "# Class-based Testbench\n\nMilestone 2" > $(PROJECT)_MS2_Class/CLASS_TB/README.md

# ---------------- MS3 (Class TB) ----------------
MS3:
	@echo "Creating $(PROJECT)_MS3_Class..."
	@mkdir -p \
		$(PROJECT)_MS3_Class/doc \
		$(PROJECT)_MS3_Class/rtl \
		$(PROJECT)_MS3_Class/CLASS_TB
	@echo "# $(PROJECT) ? MS3 (Class-based TB)" > $(PROJECT)_MS3_Class/doc/README.md
	@echo "# RTL Sources\n\nDesign files for MS3." > $(PROJECT)_MS3_Class/rtl/README.md
	@echo "# Class-based Testbench\n\nMilestone 3" > $(PROJECT)_MS3_Class/CLASS_TB/README.md

# ---------------- MS4 (UVM TB) ----------------
MS4:
	@echo "Creating $(PROJECT)_MS4_UVM..."
	@mkdir -p \
		$(PROJECT)_MS4_UVM/doc \
		$(PROJECT)_MS4_UVM/rtl \
		$(PROJECT)_MS4_UVM/UVM_TB
	@echo "# $(PROJECT) ? MS4 (UVM TB)" > $(PROJECT)_MS4_UVM/doc/README.md
	@echo "# RTL Sources\n\nDesign files for MS4." > $(PROJECT)_MS4_UVM/rtl/README.md
	@echo "# UVM Testbench\n\nMilestone 4" > $(PROJECT)_MS4_UVM/UVM_TB/README.md

# ---------------- MS5 (UVM TB) ----------------
MS5:
	@echo "Creating $(PROJECT)_MS5_UVM..."
	@mkdir -p \
		$(PROJECT)_MS5_UVM/doc \
		$(PROJECT)_MS5_UVM/rtl \
		$(PROJECT)_MS5_UVM/UVM_TB
	@echo "# $(PROJECT) ? MS5 (UVM TB)" > $(PROJECT)_MS5_UVM/doc/README.md
	@echo "# RTL Sources\n\nDesign files for MS5." > $(PROJECT)_MS5_UVM/rtl/README.md
	@echo "# UVM Testbench\n\nMilestone 5" > $(PROJECT)_MS5_UVM/UVM_TB/README.md

# ---------------- CLEAN ----------------
clean:
	@echo "Removing all milestone directories for project $(PROJECT)..."
	@rm -rf \
		$(PROJECT)_MS1_Trad \
		$(PROJECT)_MS2_Class \
		$(PROJECT)_MS3_Class \
		$(PROJECT)_MS4_UVM \
		$(PROJECT)_MS5_UVM \
		$(PROJECT)_FINAL
