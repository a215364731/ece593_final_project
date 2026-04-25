// =============================================================================
// monitor.sv
// AXI4-Lite Bus Monitor
//
// Passively observes all five AXI4-Lite channels and reconstructs complete
// write and read transactions, which are forwarded to the scoreboard via
// separate write and read mailboxes.
//
// The monitor reconstructs transactions at the handshake level:
//   Write: captures AW + W channels (independently), merges them, then
//          captures the B response into one txn_t and sends to mon2scb_wr.
//   Read:  captures the AR address and the R response into one txn_t and
//          sends to mon2scb_rd.
//
// Both paths run as concurrent threads started from run().
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

  mailbox #(txn_t) mon2scb_wr;   // completed write transactions
  mailbox #(txn_t) mon2scb_rd;   // completed read transactions

  bit verbose = 1;

  // --------------------------------------------------------------------------
  // Internal staging (AW and W may arrive in different cycles)
  // --------------------------------------------------------------------------
  local mailbox #(txn_t) aw_mbx;   // AW captures awaiting a W
  local mailbox #(txn_t) w_mbx;    // W captures awaiting an AW

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
  endfunction

  // --------------------------------------------------------------------------
  // run() - launches all monitor threads
  // --------------------------------------------------------------------------
  task run();
    fork
      monitor_aw();   // snoop AW channel -> aw_mbx
      monitor_w();    // snoop W  channel -> w_mbx
      merge_write();  // merge aw_mbx + w_mbx -> wait for B -> mon2scb_wr
      monitor_read(); // snoop AR + R       -> mon2scb_rd
    join_none
  endtask

  // --------------------------------------------------------------------------
  // monitor_aw: capture every AW handshake
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
  // monitor_w: capture every W handshake
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
  // merge_write: pair AW + W, then wait for B response
  // --------------------------------------------------------------------------
  local task merge_write();
    txn_t aw_txn, w_txn, merged;
    forever begin
      // Both arrive in any order; pick one, then wait for the other
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
  // monitor_read: capture AR + R pair
  // --------------------------------------------------------------------------
  local task monitor_read();
    forever begin
      txn_t t = new();
      t.mode = TXN_READ;

      // AR handshake
      @(vif.monitor_cb iff (vif.monitor_cb.arvalid && vif.monitor_cb.arready));
      t.addr = vif.monitor_cb.araddr;
      t.prot = vif.monitor_cb.arprot;

      // R handshake
      @(vif.monitor_cb iff (vif.monitor_cb.rvalid && vif.monitor_cb.rready));
      t.rdata = vif.monitor_cb.rdata;
      t.rresp = vif.monitor_cb.rresp;

      if (verbose) t.print("MON");
      mon2scb_rd.put(t);
    end
  endtask

endclass

`endif // AXI_MONITOR_SV
