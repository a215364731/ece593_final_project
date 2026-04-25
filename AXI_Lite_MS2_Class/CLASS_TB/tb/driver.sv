// =============================================================================
// driver.sv
// AXI4-Lite Bus Functional Model - Driver
//
// Pulls transaction objects from the gen2drv mailbox and drives them
// onto the AXI4-Lite interface.  Write address and write data channels are
// driven concurrently (as a real master would), then waits for the B response.
// Read transactions drive the AR channel then capture the R channel.
//
// Knobs:
//   aw_delay_cycles  - Random back-pressure on AW valid (0..N cycles)
//   w_delay_cycles   - Random back-pressure on W valid
//   ar_delay_cycles  - Random back-pressure on AR valid
//   b_ready_delay    - Random delay before asserting bready
//   r_ready_delay    - Random delay before asserting rready
// =============================================================================

`ifndef AXI_DRIVER_SV
`define AXI_DRIVER_SV

`include "transaction.sv"

class driver #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12
);

  typedef transaction #(DATA_WIDTH, ADDR_WIDTH) txn_t;

  // --------------------------------------------------------------------------
  // Interface handle and mailbox
  // --------------------------------------------------------------------------
  virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif;
  mailbox #(txn_t) gen2drv;

  // --------------------------------------------------------------------------
  // Knobs (randomise-able by the test)
  // --------------------------------------------------------------------------
  int unsigned max_aw_delay   = 3;
  int unsigned max_w_delay    = 3;
  int unsigned max_ar_delay   = 3;
  int unsigned max_b_delay    = 2;
  int unsigned max_r_delay    = 2;
  bit          verbose        = 1;

  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(
    virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif,
    mailbox #(txn_t) mbx
  );
    this.vif     = vif;
    this.gen2drv = mbx;
  endfunction

  // --------------------------------------------------------------------------
  // run()
  // --------------------------------------------------------------------------
  task run();
    txn_t txn;

    // De-assert all master outputs while in reset
    @(posedge vif.clk iff vif.resetn);
    @(vif.master_cb);

    forever begin
      gen2drv.get(txn);
      if (verbose) txn.print("DRV");
      if (txn.mode == TXN_WRITE)
        drive_write(txn);
      else
        drive_read(txn);
    end
  endtask

  // --------------------------------------------------------------------------
  // drive_write: AW + W channels in parallel, then B handshake
  // --------------------------------------------------------------------------
  task automatic drive_write(txn_t txn);
    // Fork AW and W channel drives; join when both have completed their
    // respective handshakes so they can overlap (standard AXI behaviour).
    fork
      drive_aw(txn);
      drive_w(txn);
    join

    // B channel: assert bready after optional delay
    drive_b(txn);
  endtask

  // ---------- AW channel ----------
  task automatic drive_aw(txn_t txn);
    int delay = $urandom_range(0, max_aw_delay);
    repeat (delay) @(vif.master_cb);

    vif.master_cb.awvalid <= 1'b1;
    vif.master_cb.awaddr  <= txn.addr;
    vif.master_cb.awprot  <= txn.prot;

    // Wait for ready
    @(vif.master_cb iff vif.master_cb.awready);
    vif.master_cb.awvalid <= 1'b0;
    vif.master_cb.awaddr  <= '0;
  endtask

  // ---------- W channel ----------
  task automatic drive_w(txn_t txn);
    int delay = $urandom_range(0, max_w_delay);
    repeat (delay) @(vif.master_cb);

    vif.master_cb.wvalid <= 1'b1;
    vif.master_cb.wdata  <= txn.wdata;
    vif.master_cb.wstrb  <= txn.wstrb;

    @(vif.master_cb iff vif.master_cb.wready);
    vif.master_cb.wvalid <= 1'b0;
    vif.master_cb.wdata  <= '0;
    vif.master_cb.wstrb  <= '0;
  endtask

  // ---------- B channel ----------
  task automatic drive_b(txn_t txn);
    int delay = $urandom_range(0, max_b_delay);
    repeat (delay) @(vif.master_cb);

    vif.master_cb.bready <= 1'b1;
    @(vif.master_cb iff vif.master_cb.bvalid);
    vif.master_cb.bready <= 1'b0;
  endtask

  // --------------------------------------------------------------------------
  // drive_read: AR channel then R channel
  // --------------------------------------------------------------------------
  task automatic drive_read(txn_t txn);
    int delay;

    // AR channel
    delay = $urandom_range(0, max_ar_delay);
    repeat (delay) @(vif.master_cb);

    vif.master_cb.arvalid <= 1'b1;
    vif.master_cb.araddr  <= txn.addr;
    vif.master_cb.arprot  <= txn.prot;

    @(vif.master_cb iff vif.master_cb.arready);
    vif.master_cb.arvalid <= 1'b0;
    vif.master_cb.araddr  <= '0;

    // R channel
    delay = $urandom_range(0, max_r_delay);
    repeat (delay) @(vif.master_cb);

    vif.master_cb.rready <= 1'b1;
    @(vif.master_cb iff vif.master_cb.rvalid);
    vif.master_cb.rready <= 1'b0;
  endtask

endclass

`endif // AXI_DRIVER_SV
