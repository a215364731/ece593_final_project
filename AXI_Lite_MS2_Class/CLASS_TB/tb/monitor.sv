// =============================================================================
// monitor.sv  (UPDATED FOR MS2 — publishes to coverage mailboxes too)
// AXI4-Lite Bus Monitor
//
// Passively observes all five AXI4-Lite channels and reconstructs complete
// write and read transactions, which are forwarded to:
//   - the scoreboard via mon2scb_wr / mon2scb_rd
//   - the coverage subscriber via mon2cov_wr / mon2cov_rd  (NEW)
//
// Two consumers receive a copy of each transaction so coverage continues
// to be collected even if the scoreboard is bypassed.
// =============================================================================

`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV

`include "transaction.sv"

class monitor #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12
);

  typedef transaction #(DATA_WIDTH, ADDR_WIDTH) txn_t;

  // --------------------------------------------------------------------------
  // Interface handle and output mailboxes
  // --------------------------------------------------------------------------
  virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif;

  mailbox #(txn_t) mon2scb_wr;   // completed write txns -> scoreboard
  mailbox #(txn_t) mon2scb_rd;   // completed read  txns -> scoreboard
  mailbox #(txn_t) mon2cov_wr;   // completed write txns -> coverage  (NEW)
  mailbox #(txn_t) mon2cov_rd;   // completed read  txns -> coverage  (NEW)

  bit verbose = 1;

  // --------------------------------------------------------------------------
  // Internal staging (AW and W may arrive in different cycles)
  // --------------------------------------------------------------------------
  local mailbox #(txn_t) aw_mbx;
  local mailbox #(txn_t) w_mbx;

  // --------------------------------------------------------------------------
  // Constructor (signature CHANGED — two extra mailbox arguments)
  // --------------------------------------------------------------------------
  function new(
    virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif,
    mailbox #(txn_t) mbx_scb_wr,
    mailbox #(txn_t) mbx_scb_rd,
    mailbox #(txn_t) mbx_cov_wr,
    mailbox #(txn_t) mbx_cov_rd
  );
    this.vif        = vif;
    this.mon2scb_wr = mbx_scb_wr;
    this.mon2scb_rd = mbx_scb_rd;
    this.mon2cov_wr = mbx_cov_wr;
    this.mon2cov_rd = mbx_cov_rd;
    aw_mbx = new();
    w_mbx  = new();
  endfunction

  // --------------------------------------------------------------------------
  // run() - launches all monitor threads
  // --------------------------------------------------------------------------
  task run();
    fork
      monitor_aw();
      monitor_w();
      merge_write();
      monitor_read();
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
  // merge_write — pair AW + W, then wait for B response, then publish
  // --------------------------------------------------------------------------
  local task merge_write();
    txn_t aw_txn, w_txn, merged, cov_copy;
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

      // Publish to scoreboard
      mon2scb_wr.put(merged);

      // Publish a separate copy to coverage (avoids cross-component aliasing)
      cov_copy       = new();
      cov_copy.mode  = merged.mode;
      cov_copy.addr  = merged.addr;
      cov_copy.prot  = merged.prot;
      cov_copy.wdata = merged.wdata;
      cov_copy.wstrb = merged.wstrb;
      cov_copy.bresp = merged.bresp;
      mon2cov_wr.put(cov_copy);
    end
  endtask

  // --------------------------------------------------------------------------
  // monitor_read — capture AR + R pair, then publish to scb + cov
  // --------------------------------------------------------------------------
  local task monitor_read();
    txn_t t, cov_copy;
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

      // Publish to scoreboard
      mon2scb_rd.put(t);

      // Publish a separate copy to coverage
      cov_copy       = new();
      cov_copy.mode  = t.mode;
      cov_copy.addr  = t.addr;
      cov_copy.prot  = t.prot;
      cov_copy.rdata = t.rdata;
      cov_copy.rresp = t.rresp;
      mon2cov_rd.put(cov_copy);
    end
  endtask

endclass

`endif // AXI_MONITOR_SV
