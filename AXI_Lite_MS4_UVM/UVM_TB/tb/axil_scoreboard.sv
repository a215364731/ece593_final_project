// =============================================================================
// axil_scoreboard.sv
// AXI4-Lite UVM Scoreboard  (replaces scoreboard.sv)
//
// Migration notes:
//   - Extends uvm_scoreboard instead of plain class
//   - The blocking mailbox.get() loops are removed; UVM pushes transactions in
//   - report() moved to report_phase() called automatically by UVM
//   - Shadow memory, byte-strobe logic, and all covergroups are unchanged
//   - MEM_INIT string parameter passed via uvm_config_db from the test
// =============================================================================

`ifndef AXIL_SCOREBOARD_SV
`define AXIL_SCOREBOARD_SV

`include "axil_seq_item.sv"

class axil_scoreboard #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
) extends uvm_scoreboard;

  typedef axil_seq_item #(DATA_WIDTH, ADDR_WIDTH) item_t;

  `uvm_component_param_utils(axil_scoreboard #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH))

  localparam int unsigned STRB_WIDTH     = DATA_WIDTH / 8;
  localparam int unsigned BYTES_PER_WORD = DATA_WIDTH / 8;

  // Analysis imp ports — replace mon2scb_wr / mon2scb_rd mailboxes
  uvm_analysis_imp #(item_t, axil_scoreboard #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)) analysis_imp;

  item_t transactions[$];

  // --------------------------------------------------------------------------
  // Shadow memory model  (unchanged from scoreboard.sv)
  // --------------------------------------------------------------------------
  local logic [DATA_WIDTH-1:0] shadow_mem [0:MEM_DEPTH-1];

  // --------------------------------------------------------------------------
  // Statistics
  // --------------------------------------------------------------------------
  int unsigned writes_checked = 0;
  int unsigned reads_checked  = 0;
  int unsigned errors         = 0;

  // --------------------------------------------------------------------------
  // Functional coverage — Transaction-Level  (unchanged from scoreboard.sv)
  // --------------------------------------------------------------------------
  logic [ADDR_WIDTH-1:0]  cov_addr;
  logic [STRB_WIDTH-1:0]  cov_wstrb;
  logic [1:0]             cov_bresp;
  logic [1:0]             cov_rresp;
  bit                     cov_in_range;

  int unsigned prev_op = 0;
  int unsigned curr_op = 0;

  covergroup cg_bresp;
    option.per_instance = 1;
    option.name         = "cg_bresp";
    BRESP_VAL: coverpoint cov_bresp {
      bins okay   = {2'b00};
      bins slverr = {2'b10};
      illegal_bins exokay_decerr = {2'b01, 2'b11};
    }
  endgroup

  covergroup cg_wstrb;
    option.per_instance = 1;
    option.name         = "cg_wstrb";
    WSTRB_VAL: coverpoint cov_wstrb {
      illegal_bins all_zero  = {0};
      bins single_byte[]     = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
      bins two_byte[]        = {4'b0011, 4'b0110, 4'b1100, 4'b1001, 4'b0101, 4'b1010};
      bins three_byte[]      = {4'b0111, 4'b1110, 4'b1011, 4'b1101};
      bins all_bytes         = {4'b1111};
    }
  endgroup

  covergroup cg_oor;
    option.per_instance = 1;
    option.name         = "cg_oor";
    IN_RANGE: coverpoint cov_in_range {
      bins in_range  = {1};
      bins out_range = {0};
    }
    OP_TYPE: coverpoint curr_op {
      bins write_op = {1};
      bins read_op  = {2};
      illegal_bins none = {0};
    }
    RESP_W: coverpoint cov_bresp iff (curr_op == 1) {
      bins okay   = {2'b00};
      bins slverr = {2'b10};
    }
    RESP_R: coverpoint cov_rresp iff (curr_op == 2) {
      bins okay   = {2'b00};
      bins slverr = {2'b10};
    }
    X_WR_RANGE_RESP: cross IN_RANGE, RESP_W iff (curr_op == 1) {
      ignore_bins n_a1 = binsof(IN_RANGE.in_range)  && binsof(RESP_W.slverr);
      ignore_bins n_a2 = binsof(IN_RANGE.out_range) && binsof(RESP_W.okay);
    }
    X_RD_RANGE_RESP: cross IN_RANGE, RESP_R iff (curr_op == 2) {
      ignore_bins n_a1 = binsof(IN_RANGE.in_range)  && binsof(RESP_R.slverr);
      ignore_bins n_a2 = binsof(IN_RANGE.out_range) && binsof(RESP_R.okay);
    }
  endgroup

  covergroup cg_rresp;
    option.per_instance = 1;
    option.name         = "cg_rresp";
    RRESP_VAL: coverpoint cov_rresp {
      bins okay   = {2'b00};
      bins slverr = {2'b10};
      illegal_bins exokay_decerr = {2'b01, 2'b11};
    }
  endgroup

  covergroup cg_addr;
    option.per_instance = 1;
    option.name         = "cg_addr";
    ADDR_BIN: coverpoint cov_addr {
      bins q1  = {[0                           : (MEM_DEPTH/4)*STRB_WIDTH - 1]};
      bins q2  = {[(MEM_DEPTH/4)*STRB_WIDTH    : (MEM_DEPTH/2)*STRB_WIDTH - 1]};
      bins q3  = {[(MEM_DEPTH/2)*STRB_WIDTH    : (3*MEM_DEPTH/4)*STRB_WIDTH - 1]};
      bins q4  = {[(3*MEM_DEPTH/4)*STRB_WIDTH  : (MEM_DEPTH)*STRB_WIDTH - 1]};
      bins oor = default;
    }
  endgroup

  covergroup cg_b2b;
    option.per_instance = 1;
    option.name         = "cg_b2b";
    PREV_OP: coverpoint prev_op {
      bins write_prev = {1};
      bins read_prev  = {2};
      ignore_bins first = {0};
    }
    CURR_OP: coverpoint curr_op {
      bins write_curr = {1};
      bins read_curr  = {2};
      illegal_bins none = {0};
    }
    X_PAIR: cross PREV_OP, CURR_OP;
  endgroup

  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    foreach (shadow_mem[i]) shadow_mem[i] = '0;
    cg_bresp = new();
    cg_wstrb = new();
    cg_oor   = new();
    cg_rresp = new();
    cg_addr  = new();
    cg_b2b   = new();
    `uvm_info("SCB", "axil_scoreboard created", UVM_HIGH)
  endfunction

  // --------------------------------------------------------------------------
  // build_phase — create analysis imp ports; load optional mem init file
  // --------------------------------------------------------------------------
  virtual function void build_phase(uvm_phase phase);
    string mem_init;
    super.build_phase(phase);
    analysis_imp = new("analysis_imp", this);

    if (uvm_config_db #(string)::get(this, "", "mem_init", mem_init) &&
        mem_init != "")
      $readmemh(mem_init, shadow_mem);
  endfunction

  function void write(item_t txn);
    transactions.push_back(txn);
  endfunction
  
  function void check_writes(item_t txn);
    writes_checked++;
    update_shadow(txn.addr, txn.wdata, txn.wstrb);

    if (txn.bresp !== 2'b00) begin
      `uvm_error("SCB", $sformatf(
        "WRITE ERROR: bresp=0b%02b expected OKAY(00) addr=0x%0h", txn.bresp, txn.addr))
      errors++;
    end else begin
      `uvm_info("SCB", $sformatf(
        "WRITE OK  addr=0x%0h data=0x%0h strb=0b%0b bresp=%0b",
        txn.addr, txn.wdata, txn.wstrb, txn.bresp), UVM_HIGH)
    end

    cov_addr     = txn.addr;
    cov_wstrb    = txn.wstrb;
    cov_bresp    = txn.bresp;
    cov_rresp    = '0;
    cov_in_range = compute_in_range(txn.addr);
    prev_op      = curr_op;
    curr_op      = 1;
    cg_bresp.sample();
    cg_wstrb.sample();
    cg_oor.sample();
    cg_addr.sample();
    cg_b2b.sample();
  endfunction

  function void check_reads(item_t txn);
    logic [DATA_WIDTH-1:0] expected;
    int unsigned           word_idx;
    reads_checked++;

    if (txn.rresp !== 2'b00) begin
      `uvm_error("SCB", $sformatf(
        "READ ERROR: rresp=0b%02b expected OKAY(00) addr=0x%0h", txn.rresp, txn.addr))
      errors++;
    end

    word_idx = addr_to_idx(txn.addr);
    expected = shadow_mem[word_idx];
    if (txn.rdata !== expected) begin
      `uvm_error("SCB", $sformatf(
        "READ MISMATCH: addr=0x%0h got=0x%0h expected=0x%0h",
        txn.addr, txn.rdata, expected))
      errors++;
    end else begin
      `uvm_info("SCB", $sformatf(
        "READ OK  addr=0x%0h data=0x%0h rresp=%0b",
        txn.addr, txn.rdata, txn.rresp), UVM_HIGH)
    end

    cov_addr     = txn.addr;
    cov_wstrb    = '0;
    cov_bresp    = '0;
    cov_rresp    = txn.rresp;
    cov_in_range = compute_in_range(txn.addr);
    prev_op      = curr_op;
    curr_op      = 2;
    cg_rresp.sample();
    cg_oor.sample();
    cg_addr.sample();
    cg_b2b.sample();
  endfunction

  // --------------------------------------------------------------------------
  // Shadow memory helpers  (unchanged from scoreboard.sv)
  // --------------------------------------------------------------------------
  local function void update_shadow(
    logic [ADDR_WIDTH-1:0]  addr,
    logic [DATA_WIDTH-1:0]  wdata,
    logic [STRB_WIDTH-1:0]  wstrb
  );
    int unsigned idx = addr_to_idx(addr);
    if (idx >= MEM_DEPTH) begin
      `uvm_warning("SCB", $sformatf(
        "update_shadow: address 0x%0h out of range (MEM_DEPTH=%0d)", addr, MEM_DEPTH))
      return;
    end
    for (int b = 0; b < STRB_WIDTH; b++)
      if (wstrb[b]) shadow_mem[idx][b*8 +: 8] = wdata[b*8 +: 8];
  endfunction

  local function int unsigned addr_to_idx(logic [ADDR_WIDTH-1:0] addr);
    return int'(addr) / BYTES_PER_WORD;
  endfunction

  local function bit compute_in_range(logic [ADDR_WIDTH-1:0] addr);
    return (int'(addr) / BYTES_PER_WORD < MEM_DEPTH);
  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      item_t txn;
      wait(transactions.size() > 0);
      txn = transactions.pop_front();
      if (txn.is_write) check_writes(txn);
      else if (txn.is_read) check_reads(txn);
    end
  endtask
  // --------------------------------------------------------------------------
  // report_phase — replaces report(); called automatically by UVM
  // --------------------------------------------------------------------------
  virtual function void report_phase(uvm_phase phase);
    real avg_pct;

    `uvm_info("SCB", "======================================================", UVM_NONE)
    `uvm_info("SCB", "SCOREBOARD REPORT", UVM_NONE)
    `uvm_info("SCB", $sformatf("  Writes checked : %0d", writes_checked), UVM_NONE)
    `uvm_info("SCB", $sformatf("  Reads  checked : %0d", reads_checked),  UVM_NONE)
    `uvm_info("SCB", $sformatf("  Errors found   : %0d", errors),         UVM_NONE)
    if (errors == 0)
      `uvm_info("SCB", "  RESULT: ** PASS **", UVM_NONE)
    else
      `uvm_error("SCB", $sformatf("  RESULT: ** FAIL ** (%0d errors)", errors))
    `uvm_info("SCB", "======================================================", UVM_NONE)

    avg_pct = (cg_bresp.get_inst_coverage()
             + cg_wstrb.get_inst_coverage()
             + cg_oor.get_inst_coverage()
             + cg_rresp.get_inst_coverage()
             + cg_addr.get_inst_coverage()
             + cg_b2b.get_inst_coverage()) / 6.0;

    `uvm_info("SCB", "FUNCTIONAL COVERAGE (Transaction-Level)", UVM_NONE)
    `uvm_info("SCB", $sformatf("  cg_bresp  (FV-005)     : %6.2f %%", cg_bresp.get_inst_coverage()), UVM_NONE)
    `uvm_info("SCB", $sformatf("  cg_wstrb  (FV-006)     : %6.2f %%", cg_wstrb.get_inst_coverage()), UVM_NONE)
    `uvm_info("SCB", $sformatf("  cg_oor    (FV-007/010) : %6.2f %%", cg_oor.get_inst_coverage()),   UVM_NONE)
    `uvm_info("SCB", $sformatf("  cg_rresp  (FV-009)     : %6.2f %%", cg_rresp.get_inst_coverage()), UVM_NONE)
    `uvm_info("SCB", $sformatf("  cg_addr   (FV-012)     : %6.2f %%", cg_addr.get_inst_coverage()),  UVM_NONE)
    `uvm_info("SCB", $sformatf("  cg_b2b    (FV-014)     : %6.2f %%", cg_b2b.get_inst_coverage()),   UVM_NONE)
    `uvm_info("SCB", $sformatf("  Avg (txn-level)        : %6.2f %%", avg_pct),                      UVM_NONE)
    `uvm_info("SCB", "======================================================", UVM_NONE)
  endfunction

endclass

`endif // AXIL_SCOREBOARD_SV
