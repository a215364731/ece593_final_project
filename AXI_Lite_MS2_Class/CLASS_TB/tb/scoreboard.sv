// =============================================================================
// scoreboard.sv  (UPDATED FOR MS2 — functional coverage embedded)
// AXI4-Lite Scoreboard
//
// Maintains a software model of the DUT's internal memory and checks every
// observed transaction against expected values.
//
// Functional coverage embedded (transaction-level, V-Plan §5.2):
//   FV-005    : cg_bresp     — BRESP code × BREADY-stall delay bin
//   FV-006    : cg_wstrb     — All 16 WSTRB byte-lane patterns
//   FV-007/010: cg_oor       — In-range / out-of-range × WR/RD × response
//   FV-009    : cg_rresp     — RRESP code
//   FV-012    : cg_addr      — Word address bins across MEM_DEPTH
//   FV-014    : cg_b2b       — Back-to-back transaction ordering pairs
//
// Cycle-level coverage (cg_reset, cg_aw_w_hs, cg_ar_hs, cg_fwd, cg_backpressure)
// lives in monitor.sv since the monitor has direct visibility of the bus
// signals on every clock edge.
// =============================================================================

`ifndef AXI_SCOREBOARD_SV
`define AXI_SCOREBOARD_SV

`include "transaction.sv"

class scoreboard #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256,
  parameter string       MEM_INIT    = ""
);

  typedef transaction #(DATA_WIDTH, ADDR_WIDTH) txn_t;

  localparam int unsigned STRB_WIDTH     = DATA_WIDTH / 8;
  localparam int unsigned BYTES_PER_WORD = DATA_WIDTH / 8;

  // --------------------------------------------------------------------------
  // Mailboxes from monitor
  // --------------------------------------------------------------------------
  mailbox #(txn_t) mon2scb_wr;
  mailbox #(txn_t) mon2scb_rd;

  // --------------------------------------------------------------------------
  // Shadow memory model
  // --------------------------------------------------------------------------
  local logic [DATA_WIDTH-1:0] shadow_mem   [0:MEM_DEPTH-1];

  // --------------------------------------------------------------------------
  // Statistics
  // --------------------------------------------------------------------------
  int unsigned writes_checked = 0;
  int unsigned reads_checked  = 0;
  int unsigned errors         = 0;

  bit verbose = 1;

  // ==========================================================================
  // FUNCTIONAL COVERAGE — Transaction-Level
  // Sampled values are populated by check_writes() / check_reads() before
  // calling .sample() on each covergroup.
  // ==========================================================================

  // Sampled values
  logic [ADDR_WIDTH-1:0]      cov_addr;
  logic [STRB_WIDTH-1:0]      cov_wstrb;
  logic [1:0]                 cov_bresp;
  logic [1:0]                 cov_rresp;
  bit                         cov_in_range;

  // Op type tracker for cg_b2b: 0=none, 1=write, 2=read
  int unsigned                prev_op = 0;
  int unsigned                curr_op = 0;

  // -- cg_bresp (FV-005) ------------------------------------------------------
  covergroup cg_bresp;
    option.per_instance = 1;
    option.name         = "cg_bresp";
    BRESP_VAL: coverpoint cov_bresp {
      bins okay   = {2'b00};
      bins slverr = {2'b10};
      illegal_bins exokay_decerr = {2'b01, 2'b11};
    }
  endgroup

  // -- cg_wstrb (FV-006) ------------------------------------------------------
  covergroup cg_wstrb;
    option.per_instance = 1;
    option.name         = "cg_wstrb";
    WSTRB_VAL: coverpoint cov_wstrb {
      illegal_bins all_zero = {0};
      bins single_byte[]    = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
      bins two_byte[]       = {4'b0011, 4'b0110, 4'b1100, 4'b1001, 4'b0101, 4'b1010};
      bins three_byte[]     = {4'b0111, 4'b1110, 4'b1011, 4'b1101};
      bins all_bytes        = {4'b1111};
    }
  endgroup

  // -- cg_oor (FV-007 / FV-010) -----------------------------------------------
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

  // -- cg_rresp (FV-009) ------------------------------------------------------
  covergroup cg_rresp;
    option.per_instance = 1;
    option.name         = "cg_rresp";
    RRESP_VAL: coverpoint cov_rresp {
      bins okay   = {2'b00};
      bins slverr = {2'b10};
      illegal_bins exokay_decerr = {2'b01, 2'b11};
    }
  endgroup

  // -- cg_addr (FV-012) -------------------------------------------------------
  covergroup cg_addr;
    option.per_instance = 1;
    option.name         = "cg_addr";
    ADDR_BIN: coverpoint cov_addr {
      bins q1   = {[0                                 : (MEM_DEPTH/4)*STRB_WIDTH - 1]};
      bins q2   = {[(MEM_DEPTH/4)*STRB_WIDTH          : (MEM_DEPTH/2)*STRB_WIDTH - 1]};
      bins q3   = {[(MEM_DEPTH/2)*STRB_WIDTH          : (3*MEM_DEPTH/4)*STRB_WIDTH - 1]};
      bins q4   = {[(3*MEM_DEPTH/4)*STRB_WIDTH        : (MEM_DEPTH)*STRB_WIDTH - 1]};
      bins oor  = default;
    }
  endgroup

  // -- cg_b2b (FV-014) --------------------------------------------------------
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
  function new(
    mailbox #(txn_t) mbx_wr,
    mailbox #(txn_t) mbx_rd
  );
    this.mon2scb_wr = mbx_wr;
    this.mon2scb_rd = mbx_rd;

    foreach (shadow_mem[i]) shadow_mem[i] = '0;
    if (MEM_INIT != "") $readmemh(MEM_INIT, shadow_mem);

    // Instantiate covergroups
    cg_bresp = new();
    cg_wstrb = new();
    cg_oor   = new();
    cg_rresp = new();
    cg_addr  = new();
    cg_b2b   = new();
  endfunction

  // --------------------------------------------------------------------------
  // run() - launches write and read check threads
  // --------------------------------------------------------------------------
  task run();
    fork
      check_writes();
      check_reads();
    join_none
  endtask

  // --------------------------------------------------------------------------
  // check_writes
  // --------------------------------------------------------------------------
  task check_writes();
    txn_t txn;
    forever begin
      mon2scb_wr.get(txn);
      writes_checked++;

      // --- Update shadow memory ---
      update_shadow(txn.addr, txn.wdata, txn.wstrb);

      // --- Check bresp ---
      if (txn.bresp !== 2'b00) begin
        $error("[SCB] WRITE ERROR: bresp=0b%02b expected OKAY(00) addr=0x%0h",
               txn.bresp, txn.addr);
        errors++;
      end else if (verbose) begin
        $display("[SCB] WRITE OK  addr=0x%0h data=0x%0h strb=0b%0b bresp=%0b",
                 txn.addr, txn.wdata, txn.wstrb, txn.bresp);
      end

      // --- Sample functional coverage ---
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
    end
  endtask

  // --------------------------------------------------------------------------
  // check_reads
  // --------------------------------------------------------------------------
  task check_reads();
    txn_t txn;
    logic [DATA_WIDTH-1:0] expected;
    int unsigned word_idx;
    forever begin
      mon2scb_rd.get(txn);
      reads_checked++;

      // --- Check rresp ---
      if (txn.rresp !== 2'b00) begin
        $error("[SCB] READ  ERROR: rresp=0b%02b expected OKAY(00) addr=0x%0h",
               txn.rresp, txn.addr);
        errors++;
      end

      // --- Check rdata against shadow ---
      word_idx = addr_to_idx(txn.addr);
      expected = shadow_mem[word_idx];
      if (txn.rdata !== expected) begin
        $error("[SCB] READ  MISMATCH: addr=0x%0h got=0x%0h expected=0x%0h",
                txn.addr, txn.rdata, expected);
        errors++;
      end else if (verbose) begin
        $display("[SCB] READ  OK  addr=0x%0h data=0x%0h rresp=%0b",
                 txn.addr, txn.rdata, txn.rresp);
      end

      // --- Sample functional coverage ---
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
    end
  endtask

  // --------------------------------------------------------------------------
  // Shadow memory helpers
  // --------------------------------------------------------------------------
  local function void update_shadow(
    logic [ADDR_WIDTH-1:0]      addr,
    logic [DATA_WIDTH-1:0]      wdata,
    logic [STRB_WIDTH-1:0]      wstrb
  );
    int unsigned idx = addr_to_idx(addr);
    if (idx >= MEM_DEPTH) begin
      $warning("[SCB] update_shadow: address 0x%0h out of range (MEM_DEPTH=%0d)", addr, MEM_DEPTH);
      return;
    end
    for (int b = 0; b < STRB_WIDTH; b++) begin
      if (wstrb[b])
        shadow_mem[idx][b*8 +: 8] = wdata[b*8 +: 8];
    end
  endfunction

  local function int unsigned addr_to_idx(logic [ADDR_WIDTH-1:0] addr);
    return int'(addr) / BYTES_PER_WORD;
  endfunction

  local function bit compute_in_range(logic [ADDR_WIDTH-1:0] addr);
    int unsigned word_idx;
    word_idx = int'(addr) / BYTES_PER_WORD;
    return (word_idx < MEM_DEPTH);
  endfunction

  // --------------------------------------------------------------------------
  // report()
  // --------------------------------------------------------------------------
  function void report();
    real avg_pct;

    $display("======================================================");
    $display("[SCB] SCOREBOARD REPORT");
    $display("  Writes checked : %0d", writes_checked);
    $display("  Reads  checked : %0d", reads_checked);
    $display("  Errors found   : %0d", errors);
    if (errors == 0)
      $display("  RESULT: ** PASS **");
    else
      $display("  RESULT: ** FAIL ** (%0d errors)", errors);
    $display("======================================================");

    avg_pct = (cg_bresp.get_inst_coverage()
             + cg_wstrb.get_inst_coverage()
             + cg_oor.get_inst_coverage()
             + cg_rresp.get_inst_coverage()
             + cg_addr.get_inst_coverage()
             + cg_b2b.get_inst_coverage()) / 6.0;

    $display("[SCB] FUNCTIONAL COVERAGE (Transaction-Level)");
    $display("  cg_bresp  (FV-005)         : %6.2f %%", cg_bresp.get_inst_coverage());
    $display("  cg_wstrb  (FV-006)         : %6.2f %%", cg_wstrb.get_inst_coverage());
    $display("  cg_oor    (FV-007/010)     : %6.2f %%", cg_oor.get_inst_coverage());
    $display("  cg_rresp  (FV-009)         : %6.2f %%", cg_rresp.get_inst_coverage());
    $display("  cg_addr   (FV-012)         : %6.2f %%", cg_addr.get_inst_coverage());
    $display("  cg_b2b    (FV-014)         : %6.2f %%", cg_b2b.get_inst_coverage());
    $display("  Avg (txn-level)            : %6.2f %%", avg_pct);
    $display("======================================================");
  endfunction

endclass

`endif // AXI_SCOREBOARD_SV
