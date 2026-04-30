// =============================================================================
// monitor.sv  (UPDATED FOR MS2 — cycle-level functional coverage embedded)
// AXI4-Lite Bus Monitor
//
// Passively observes all five AXI4-Lite channels and reconstructs complete
// write and read transactions, which are forwarded to the scoreboard via
// separate write and read mailboxes.
//
// Functional coverage embedded (cycle-level, V-Plan §5.2):
//   FV-001    : cg_reset         — reset assertion / de-assertion
//   FV-002/003: cg_aw_w_hs       — AW vs W handshake ordering
//   FV-008    : cg_ar_hs         — AR-to-R latency bins
//   FV-011    : cg_fwd           — Same-cycle WR+RD same-address forwarding
//   FV-013    : cg_backpressure  — BREADY / RREADY stall cycles (B and R)
//
// Transaction-level coverage (cg_bresp, cg_wstrb, cg_oor, cg_rresp, cg_addr,
// cg_b2b) lives in scoreboard.sv since the scoreboard checks each completed
// transaction.
// =============================================================================

`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV

`include "transaction.sv"

class monitor #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
);

  typedef transaction #(DATA_WIDTH, ADDR_WIDTH) txn_t;

  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
  localparam int unsigned WORD_BITS  = (STRB_WIDTH > 1) ? $clog2(STRB_WIDTH) : 1;

  // --------------------------------------------------------------------------
  // Interface handle and output mailboxes
  // --------------------------------------------------------------------------
  virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif;

  mailbox #(txn_t) mon2scb_wr;
  mailbox #(txn_t) mon2scb_rd;

  bit verbose = 1;

  // --------------------------------------------------------------------------
  // Internal staging (AW and W may arrive in different cycles)
  // --------------------------------------------------------------------------
  local mailbox #(txn_t) aw_mbx;
  local mailbox #(txn_t) w_mbx;

  // ==========================================================================
  // FUNCTIONAL COVERAGE — Cycle-Level
  // Sampled values are written by the cycle-level tracker thread before
  // calling .sample() on each covergroup.
  // ==========================================================================

  // Sampled values for cycle-level covergroups
  bit         cov_reset_asserted = 0;
  bit         cov_reset_released = 0;
  bit [1:0]   cov_aw_w_order     = 0;     // 1=AW first, 2=W first, 3=concurrent
  int unsigned cov_ar_r_latency  = 0;
  int unsigned cov_b_stall_cnt   = 0;
  int unsigned cov_r_stall_cnt   = 0;
  bit         cov_fwd_event      = 0;

  // -- cg_reset (FV-001) ------------------------------------------------------
  covergroup cg_reset @(posedge vif.clk);
    option.per_instance = 1;
    option.name         = "cg_reset";
    RST_ASSERT: coverpoint vif.resetn {
      bins asserted = {0};
      bins deasserted = {1};
    }
  endgroup

  // -- cg_aw_w_hs (FV-002 / FV-003) -------------------------------------------
  covergroup cg_aw_w_hs;
    option.per_instance = 1;
    option.name         = "cg_aw_w_hs";
    AW_W_ORDER: coverpoint cov_aw_w_order {
      bins aw_first   = {2'd1};
      bins w_first    = {2'd2};
      bins concurrent = {2'd3};
      ignore_bins idle = {2'd0};
    }
  endgroup

  // -- cg_ar_hs (FV-008) ------------------------------------------------------
  covergroup cg_ar_hs;
    option.per_instance = 1;
    option.name         = "cg_ar_hs";
    AR_R_LATENCY: coverpoint cov_ar_r_latency {
      bins lat_1_cycle = {1};
      bins lat_2_cycle = {2};
      bins lat_3_cycle = {3};
      bins lat_4_to_7  = {[4:7]};
      bins lat_8_to_15 = {[8:15]};
      bins lat_long    = {[16:$]};
    }
  endgroup

  // -- cg_fwd (FV-011) --------------------------------------------------------
  covergroup cg_fwd;
    option.per_instance = 1;
    option.name         = "cg_fwd";
    FWD_HIT: coverpoint cov_fwd_event {
      bins fwd_detected = {1};
    }
  endgroup

  // -- cg_backpressure (FV-013) -----------------------------------------------
  covergroup cg_bp_b;
    option.per_instance = 1;
    option.name         = "cg_bp_b";
    B_STALL: coverpoint cov_b_stall_cnt {
      bins no_stall   = {0};
      bins stall_1_3  = {[1:3]};
      bins stall_4_7  = {[4:7]};
      bins stall_8_15 = {[8:15]};
      bins stall_long = {[16:$]};
    }
  endgroup

  covergroup cg_bp_r;
    option.per_instance = 1;
    option.name         = "cg_bp_r";
    R_STALL: coverpoint cov_r_stall_cnt {
      bins no_stall   = {0};
      bins stall_1_3  = {[1:3]};
      bins stall_4_7  = {[4:7]};
      bins stall_8_15 = {[8:15]};
      bins stall_long = {[16:$]};
    }
  endgroup

  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(
    virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif,
    mailbox #(txn_t) mbx_wr,
    mailbox #(txn_t) mbx_rd
  );
    this.vif        = vif;
    this.mon2scb_wr = mbx_wr;
    this.mon2scb_rd = mbx_rd;
    aw_mbx = new();
    w_mbx  = new();

    // Instantiate covergroups
    cg_reset    = new();
    cg_aw_w_hs  = new();
    cg_ar_hs    = new();
    cg_fwd      = new();
    cg_bp_b     = new();
    cg_bp_r     = new();
  endfunction

  // --------------------------------------------------------------------------
  // run() - launches all monitor threads
  // --------------------------------------------------------------------------
  task run();
    fork
      monitor_aw();          // snoop AW channel  -> aw_mbx
      monitor_w();           // snoop W  channel  -> w_mbx
      merge_write();         // merge aw_mbx + w_mbx -> wait for B -> mon2scb_wr
      monitor_read();        // snoop AR + R       -> mon2scb_rd
      cycle_coverage();      // cycle-level coverage tracker (NEW)
    join_none
  endtask

  // --------------------------------------------------------------------------
  // monitor_aw
  // --------------------------------------------------------------------------
  local task monitor_aw();
    forever begin
      @(vif.monitor_cb iff (vif.monitor_cb.awvalid && vif.monitor_cb.awready));
      begin
        txn_t t = new();
        t.mode = TXN_WRITE;
        t.addr = vif.monitor_cb.awaddr;
        t.prot = vif.monitor_cb.awprot;
        aw_mbx.put(t);
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // monitor_w
  // --------------------------------------------------------------------------
  local task monitor_w();
    forever begin
      @(vif.monitor_cb iff (vif.monitor_cb.wvalid && vif.monitor_cb.wready));
      begin
        txn_t t = new();
        t.mode  = TXN_WRITE;
        t.wdata = vif.monitor_cb.wdata;
        t.wstrb = vif.monitor_cb.wstrb;
        w_mbx.put(t);
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // merge_write — pair AW + W, wait for B, send to scoreboard
  // --------------------------------------------------------------------------
  local task merge_write();
    txn_t aw_txn, w_txn, merged;
    forever begin
      aw_mbx.get(aw_txn);
      w_mbx.get(w_txn);

      merged       = new();
      merged.mode  = TXN_WRITE;
      merged.addr  = aw_txn.addr;
      merged.prot  = aw_txn.prot;
      merged.wdata = w_txn.wdata;
      merged.wstrb = w_txn.wstrb;

      // Wait for B handshake
      @(vif.monitor_cb iff (vif.monitor_cb.bvalid && vif.monitor_cb.bready));
      merged.bresp = vif.monitor_cb.bresp;

      if (verbose) merged.print("MON");
      mon2scb_wr.put(merged);
    end
  endtask

  // --------------------------------------------------------------------------
  // monitor_read — capture AR + R pair, send to scoreboard
  // --------------------------------------------------------------------------
  local task monitor_read();
    txn_t t;
    forever begin
      t = new();
      t.mode = TXN_READ;

      @(vif.monitor_cb iff (vif.monitor_cb.arvalid && vif.monitor_cb.arready));
      t.addr = vif.monitor_cb.araddr;
      t.prot = vif.monitor_cb.arprot;

      @(vif.monitor_cb iff (vif.monitor_cb.rvalid && vif.monitor_cb.rready));
      t.rdata = vif.monitor_cb.rdata;
      t.rresp = vif.monitor_cb.rresp;

      if (verbose) t.print("MON");
      mon2scb_rd.put(t);
    end
  endtask

  // --------------------------------------------------------------------------
  // cycle_coverage — tracks cycle-level events for the 5 cycle-level covergroups
  //
  // This task watches the bus on every clock edge and samples covergroups at
  // the appropriate moments (handshake completions, reset transitions, etc.).
  // --------------------------------------------------------------------------
  local task cycle_coverage();
    bit prev_resetn = 1;
    bit awaiting_w_after_aw = 0;
    bit awaiting_aw_after_w = 0;
    int unsigned ar_r_cnt = 0;
    bit          ar_active = 0;
    int unsigned b_stall   = 0;
    int unsigned r_stall   = 0;

    forever begin
      @(posedge vif.clk);


      // Skip the rest while in reset
      if (!vif.resetn) begin
        awaiting_w_after_aw = 0;
        awaiting_aw_after_w = 0;
        ar_active = 0;
        ar_r_cnt = 0;
        b_stall = 0;
        r_stall = 0;
        continue;
      end

      // ---- AW vs W handshake ordering ----
      begin
        bit aw_hs = vif.monitor_cb.awvalid && vif.monitor_cb.awready;
        bit w_hs  = vif.monitor_cb.wvalid  && vif.monitor_cb.wready;

        if (aw_hs && w_hs) begin
          cov_aw_w_order = 2'd3;        // concurrent
          cg_aw_w_hs.sample();
          awaiting_w_after_aw = 0;
          awaiting_aw_after_w = 0;
        end else if (aw_hs) begin
          if (awaiting_aw_after_w) begin
            cov_aw_w_order = 2'd2;      // W came first
            cg_aw_w_hs.sample();
            awaiting_aw_after_w = 0;
          end else begin
            awaiting_w_after_aw = 1;
          end
        end else if (w_hs) begin
          if (awaiting_w_after_aw) begin
            cov_aw_w_order = 2'd1;      // AW came first
            cg_aw_w_hs.sample();
            awaiting_w_after_aw = 0;
          end else begin
            awaiting_aw_after_w = 1;
          end
        end
      end

      // ---- AR -> R latency tracking ----
      begin
        bit ar_hs = vif.monitor_cb.arvalid && vif.monitor_cb.arready;
        bit r_hs  = vif.monitor_cb.rvalid  && vif.monitor_cb.rready;

        if (ar_hs) begin
          ar_active = 1;
          ar_r_cnt  = 0;
        end else if (ar_active) begin
          ar_r_cnt = ar_r_cnt + 1;
          if (r_hs) begin
            cov_ar_r_latency = ar_r_cnt;
            cg_ar_hs.sample();
            ar_active = 0;
          end
        end
      end

      // ---- BREADY backpressure ----
      begin
        if (vif.monitor_cb.bvalid && !vif.monitor_cb.bready) begin
          b_stall = b_stall + 1;
        end else if (vif.monitor_cb.bvalid && vif.monitor_cb.bready) begin
          cov_b_stall_cnt = b_stall;
          cg_bp_b.sample();
          b_stall = 0;
        end
      end

      // ---- RREADY backpressure ----
      begin
        if (vif.monitor_cb.rvalid && !vif.monitor_cb.rready) begin
          r_stall = r_stall + 1;
        end else if (vif.monitor_cb.rvalid && vif.monitor_cb.rready) begin
          cov_r_stall_cnt = r_stall;
          cg_bp_r.sample();
          r_stall = 0;
        end
      end

      // ---- Write-before-read forwarding ----
      begin
        bit aw_hs = vif.monitor_cb.awvalid && vif.monitor_cb.awready;
        bit ar_hs = vif.monitor_cb.arvalid && vif.monitor_cb.arready;

        if (aw_hs && ar_hs) begin
          // Same-cycle AW + AR — check word-address match
          logic [ADDR_WIDTH-1:0] aw_addr = vif.monitor_cb.awaddr;
          logic [ADDR_WIDTH-1:0] ar_addr = vif.monitor_cb.araddr;
          if (aw_addr[ADDR_WIDTH-1:WORD_BITS] == ar_addr[ADDR_WIDTH-1:WORD_BITS]) begin
            cov_fwd_event = 1;
            cg_fwd.sample();
            cov_fwd_event = 0;
          end
        end
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // report() - call at end of simulation
  // --------------------------------------------------------------------------
  function void report();
    real avg_pct;
    avg_pct = (cg_reset.get_inst_coverage()
             + cg_aw_w_hs.get_inst_coverage()
             + cg_ar_hs.get_inst_coverage()
             + cg_fwd.get_inst_coverage()
             + cg_bp_b.get_inst_coverage()
             + cg_bp_r.get_inst_coverage()) / 6.0;

    $display("======================================================");
    $display("[MON] FUNCTIONAL COVERAGE (Cycle-Level)");
    $display("  cg_reset          (FV-001)        : %6.2f %%", cg_reset.get_inst_coverage());
    $display("  cg_aw_w_hs        (FV-002/003)    : %6.2f %%", cg_aw_w_hs.get_inst_coverage());
    $display("  cg_ar_hs          (FV-008)        : %6.2f %%", cg_ar_hs.get_inst_coverage());
    $display("  cg_fwd            (FV-011)        : %6.2f %%", cg_fwd.get_inst_coverage());
    $display("  cg_bp_b           (FV-013 / B)    : %6.2f %%", cg_bp_b.get_inst_coverage());
    $display("  cg_bp_r           (FV-013 / R)    : %6.2f %%", cg_bp_r.get_inst_coverage());
    $display("  Avg (cycle-level)                 : %6.2f %%", avg_pct);
    $display("======================================================");
  endfunction

endclass

`endif // AXI_MONITOR_SV
