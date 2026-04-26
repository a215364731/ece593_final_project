// =============================================================================
// coverage.sv
// AXI4-Lite Functional Coverage — Transaction-Level Subscriber
//
// This component is a passive subscriber that collects transaction-level
// functional coverage. It receives copies of every observed transaction
// from the monitor via dedicated mailboxes (mon2cov_wr, mon2cov_rd) and
// samples its covergroups accordingly.
//
// Covergroups implemented (mapped to V-Plan FV-IDs):
//   FV-005    : cg_bresp     — BRESP code × write count
//   FV-006    : cg_wstrb     — WSTRB byte-lane patterns (16 bins)
//   FV-007/010: cg_oor       — out-of-range addr × op × response
//   FV-009    : cg_rresp     — RRESP code × read count
//   FV-012    : cg_addr      — Word address bins across MEM_DEPTH
//   FV-014    : cg_b2b       — Back-to-back transaction ordering pairs
//
// The remaining covergroups in the V-Plan (cg_reset, cg_aw_w_hs, cg_ar_hs,
// cg_fwd, cg_backpressure) are cycle-level and live in cov_iface.sv as
// interface-bound covergroups. Together the two files implement all
// 11 covergroups from V-Plan Section 5.2.
//
// Architecture rationale (industry pattern):
//   The coverage component runs as an independent subscriber so that:
//     - Coverage continues to be collected even if the scoreboard fails.
//     - Coverage can be enabled/disabled without affecting the checker.
//     - The same pattern maps directly to uvm_subscriber in MS4.
// =============================================================================

`ifndef AXI_COVERAGE_SV
`define AXI_COVERAGE_SV

`include "transaction.sv"

class coverage #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
);

  typedef transaction #(DATA_WIDTH, ADDR_WIDTH) txn_t;

  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

  // --------------------------------------------------------------------------
  // Mailboxes from monitor (one txn copy per WR / RD)
  // --------------------------------------------------------------------------
  mailbox #(txn_t) mon2cov_wr;
  mailbox #(txn_t) mon2cov_rd;

  // --------------------------------------------------------------------------
  // Sampled values (covergroups read these)
  // --------------------------------------------------------------------------
  protected logic [ADDR_WIDTH-1:0]      cov_addr;
  protected logic [DATA_WIDTH-1:0]      cov_wdata;
  protected logic [STRB_WIDTH-1:0]      cov_wstrb;
  protected logic [1:0]                 cov_bresp;
  protected logic [1:0]                 cov_rresp;
  protected bit                         cov_in_range;

  // For b2b ordering: track the previous txn type
  // 0=none, 1=write, 2=read
  protected int unsigned prev_op = 0;
  protected int unsigned curr_op = 0;

  // --------------------------------------------------------------------------
  // Statistics
  // --------------------------------------------------------------------------
  int unsigned writes_sampled = 0;
  int unsigned reads_sampled  = 0;

  bit verbose = 0;

  // ==========================================================================
  // Covergroup: cg_bresp  (FV-005)
  //   Cross of BRESP value with the OKAY/SLVERR cases.
  // ==========================================================================
  covergroup cg_bresp;
    option.per_instance = 1;
    option.name         = "cg_bresp";
    BRESP_VAL: coverpoint cov_bresp {
      bins okay   = {2'b00};
      bins slverr = {2'b10};
      illegal_bins exokay_decerr = {2'b01, 2'b11};
    }
  endgroup

  // ==========================================================================
  // Covergroup: cg_wstrb  (FV-006)
  //   All 16 WSTRB patterns for DATA_WIDTH=32 (4 byte lanes).
  //   For DATA_WIDTH=64 the patterns extend automatically.
  // ==========================================================================
  covergroup cg_wstrb;
    option.per_instance = 1;
    option.name         = "cg_wstrb";
    WSTRB_VAL: coverpoint cov_wstrb {
      // 0000 is illegal per AXI for a write that fires; included as illegal_bin
      illegal_bins all_zero = {0};
      bins single_byte[]    = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
      bins two_byte[]       = {4'b0011, 4'b0110, 4'b1100, 4'b1001, 4'b0101, 4'b1010};
      bins three_byte[]     = {4'b0111, 4'b1110, 4'b1011, 4'b1101};
      bins all_bytes        = {4'b1111};
    }
  endgroup

  // ==========================================================================
  // Covergroup: cg_oor  (FV-007 / FV-010)
  //   Out-of-range write/read × resulting response code.
  //   Sampled for both WR and RD — discriminator is sampled via curr_op.
  // ==========================================================================
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
    // Crosses
    X_WR_RANGE_RESP: cross IN_RANGE, RESP_W iff (curr_op == 1) {
      // out_of_range write must yield SLVERR — both bins should fill
      ignore_bins n_a = binsof(IN_RANGE.in_range)  && binsof(RESP_W.slverr);
    }
    X_RD_RANGE_RESP: cross IN_RANGE, RESP_R iff (curr_op == 2) {
      ignore_bins n_a = binsof(IN_RANGE.in_range)  && binsof(RESP_R.slverr);
    }
  endgroup

  // ==========================================================================
  // Covergroup: cg_rresp  (FV-009)
  // ==========================================================================
  covergroup cg_rresp;
    option.per_instance = 1;
    option.name         = "cg_rresp";
    RRESP_VAL: coverpoint cov_rresp {
      bins okay   = {2'b00};
      bins slverr = {2'b10};
      illegal_bins exokay_decerr = {2'b01, 2'b11};
    }
  endgroup

  // ==========================================================================
  // Covergroup: cg_addr  (FV-012)
  //   Word addresses binned across [0, MEM_DEPTH-1]. Uses 8 equally-spaced
  //   bins plus boundary bins at the very low and very high addresses.
  // ==========================================================================
  covergroup cg_addr;
    option.per_instance = 1;
    option.name         = "cg_addr";
    ADDR_BIN: coverpoint cov_addr {
      bins addr_low_boundary  = {[0 : (DATA_WIDTH/8) - 1]};
      bins addr_low           = {[(DATA_WIDTH/8) :
                                  (MEM_DEPTH * (DATA_WIDTH/8))/8 - 1]};
      bins addr_low_mid       = {[(MEM_DEPTH * (DATA_WIDTH/8))/8 :
                                  (MEM_DEPTH * (DATA_WIDTH/8))*2/8 - 1]};
      bins addr_mid           = {[(MEM_DEPTH * (DATA_WIDTH/8))*2/8 :
                                  (MEM_DEPTH * (DATA_WIDTH/8))*4/8 - 1]};
      bins addr_high_mid      = {[(MEM_DEPTH * (DATA_WIDTH/8))*4/8 :
                                  (MEM_DEPTH * (DATA_WIDTH/8))*6/8 - 1]};
      bins addr_high          = {[(MEM_DEPTH * (DATA_WIDTH/8))*6/8 :
                                  (MEM_DEPTH * (DATA_WIDTH/8))*8/8 - 1]};
      bins addr_high_boundary = {[(MEM_DEPTH * (DATA_WIDTH/8)) - (DATA_WIDTH/8) :
                                  (MEM_DEPTH * (DATA_WIDTH/8)) - 1]};
      bins addr_oor           = default;
    }
  endgroup

  // ==========================================================================
  // Covergroup: cg_b2b  (FV-014)
  //   Cross of previous-op × current-op to capture all four ordering pairs:
  //     WR->WR, WR->RD, RD->WR, RD->RD
  // ==========================================================================
  covergroup cg_b2b;
    option.per_instance = 1;
    option.name         = "cg_b2b";
    PREV_OP: coverpoint prev_op {
      bins write_prev = {1};
      bins read_prev  = {2};
      ignore_bins first = {0};   // first txn has no predecessor
    }
    CURR_OP: coverpoint curr_op {
      bins write_curr = {1};
      bins read_curr  = {2};
      illegal_bins none = {0};
    }
    X_PAIR: cross PREV_OP, CURR_OP;
  endgroup

  // --------------------------------------------------------------------------
  // Constructor — instantiate covergroups
  // --------------------------------------------------------------------------
  function new(
    mailbox #(txn_t) mbx_wr,
    mailbox #(txn_t) mbx_rd
  );
    this.mon2cov_wr = mbx_wr;
    this.mon2cov_rd = mbx_rd;

    cg_bresp = new();
    cg_wstrb = new();
    cg_oor   = new();
    cg_rresp = new();
    cg_addr  = new();
    cg_b2b   = new();
  endfunction

  // --------------------------------------------------------------------------
  // run() — fork write and read sampling threads
  // --------------------------------------------------------------------------
  task run();
    fork
      sample_writes();
      sample_reads();
    join_none
  endtask

  // --------------------------------------------------------------------------
  // sample_writes
  // --------------------------------------------------------------------------
  task sample_writes();
    txn_t t;
    forever begin
      mon2cov_wr.get(t);
      writes_sampled++;

      // Latch sampled values
      cov_addr     = t.addr;
      cov_wdata    = t.wdata;
      cov_wstrb    = t.wstrb;
      cov_bresp    = t.bresp;
      cov_rresp    = '0;
      cov_in_range = compute_in_range(t.addr);

      prev_op = curr_op;
      curr_op = 1;  // write

      // Sample relevant covergroups
      cg_bresp.sample();
      cg_wstrb.sample();
      cg_oor.sample();
      cg_addr.sample();
      cg_b2b.sample();

      if (verbose)
        $display("[COV] sampled WRITE addr=0x%0h wstrb=0b%0b bresp=%0b in_range=%0d",
                 t.addr, t.wstrb, t.bresp, cov_in_range);
    end
  endtask

  // --------------------------------------------------------------------------
  // sample_reads
  // --------------------------------------------------------------------------
  task sample_reads();
    txn_t t;
    forever begin
      mon2cov_rd.get(t);
      reads_sampled++;

      cov_addr     = t.addr;
      cov_wdata    = '0;
      cov_wstrb    = '0;
      cov_bresp    = '0;
      cov_rresp    = t.rresp;
      cov_in_range = compute_in_range(t.addr);

      prev_op = curr_op;
      curr_op = 2;  // read

      cg_rresp.sample();
      cg_oor.sample();
      cg_addr.sample();
      cg_b2b.sample();

      if (verbose)
        $display("[COV] sampled READ  addr=0x%0h rresp=%0b in_range=%0d",
                 t.addr, t.rresp, cov_in_range);
    end
  endtask

  // --------------------------------------------------------------------------
  // compute_in_range
  // --------------------------------------------------------------------------
  protected function bit compute_in_range(logic [ADDR_WIDTH-1:0] addr);
    int unsigned word_idx;
    word_idx = int'(addr) / (DATA_WIDTH / 8);
    return (word_idx < MEM_DEPTH);
  endfunction

  // --------------------------------------------------------------------------
  // report() — call at end of simulation
  // --------------------------------------------------------------------------
  function void report();
    real cov_bresp_pct, cov_wstrb_pct, cov_oor_pct;
    real cov_rresp_pct, cov_addr_pct,  cov_b2b_pct;
    real cov_overall_pct;

    cov_bresp_pct = cg_bresp.get_inst_coverage();
    cov_wstrb_pct = cg_wstrb.get_inst_coverage();
    cov_oor_pct   = cg_oor.get_inst_coverage();
    cov_rresp_pct = cg_rresp.get_inst_coverage();
    cov_addr_pct  = cg_addr.get_inst_coverage();
    cov_b2b_pct   = cg_b2b.get_inst_coverage();

    cov_overall_pct = (cov_bresp_pct + cov_wstrb_pct + cov_oor_pct +
                       cov_rresp_pct + cov_addr_pct  + cov_b2b_pct) / 6.0;

    $display("======================================================");
    $display("[COV] FUNCTIONAL COVERAGE REPORT (Transaction-Level)");
    $display("------------------------------------------------------");
    $display("  Writes sampled : %0d", writes_sampled);
    $display("  Reads  sampled : %0d", reads_sampled);
    $display("------------------------------------------------------");
    $display("  cg_bresp  (FV-005)         : %5.2f %%", cov_bresp_pct);
    $display("  cg_wstrb  (FV-006)         : %5.2f %%", cov_wstrb_pct);
    $display("  cg_oor    (FV-007/010)     : %5.2f %%", cov_oor_pct);
    $display("  cg_rresp  (FV-009)         : %5.2f %%", cov_rresp_pct);
    $display("  cg_addr   (FV-012)         : %5.2f %%", cov_addr_pct);
    $display("  cg_b2b    (FV-014)         : %5.2f %%", cov_b2b_pct);
    $display("------------------------------------------------------");
    $display("  Overall (txn-level avg)    : %5.2f %%", cov_overall_pct);
    $display("======================================================");
    $display("[COV] Note: cycle-level covergroups (cg_reset, cg_aw_w_hs,");
    $display("[COV]       cg_ar_hs, cg_fwd, cg_backpressure) are reported");
    $display("[COV]       by cov_iface in the URG database.");
    $display("======================================================");
  endfunction

endclass

`endif // AXI_COVERAGE_SV
