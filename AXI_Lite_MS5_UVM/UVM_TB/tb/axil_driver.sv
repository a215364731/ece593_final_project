// =============================================================================
// axil_driver.sv
// AXI4-Lite UVM Driver  (replaces driver.sv)
//
// Migration notes:
//   - Extends uvm_driver #(axil_seq_item) instead of plain class
//   - run_phase() replaces run()
//   - seq_item_port.get_next_item() / item_done() replace mailbox.get()
//   - Virtual interface retrieved from uvm_config_db in build_phase()
//   - All BFM tasks (drive_write, drive_read, drive_both, drive_aw, etc.)
//     are carried over unchanged
//   - do_reset() removed — reset is handled by axil_if.do_reset() in
//     testbench_top before run_test()
// =============================================================================

`ifndef AXIL_DRIVER_SV
`define AXIL_DRIVER_SV

`include "axil_seq_item.sv"

class axil_driver #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12
) extends uvm_driver #(axil_seq_item #(DATA_WIDTH, ADDR_WIDTH));

  typedef axil_seq_item #(DATA_WIDTH, ADDR_WIDTH) item_t;

  `uvm_component_param_utils(axil_driver #(DATA_WIDTH, ADDR_WIDTH))

  // Virtual interface — set in testbench_top via uvm_config_db
  virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif;

  // Knobs — set via uvm_config_db or directly in test build_phase()
  int unsigned max_aw_delay = 30;
  int unsigned max_w_delay  = 30;
  int unsigned max_ar_delay = 30;
  int unsigned max_b_delay  = 30;
  int unsigned max_r_delay  = 30;

  // Constructor
  function new(string name, uvm_component parent);
    super.new(name, parent);
    `uvm_info("DRV", "axil_driver created", UVM_HIGH)
  endfunction

  // --------------------------------------------------------------------------
  // build_phase — fetch virtual interface from config DB
  // --------------------------------------------------------------------------
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axil_if #(DATA_WIDTH, ADDR_WIDTH))::get(
          this, "*", "vif", vif))
      `uvm_fatal("DRV", "failed to get vif in uvm_config_db")
  endfunction

  // --------------------------------------------------------------------------
  // run_phase — replaces run()
  // --------------------------------------------------------------------------
  virtual task run_phase(uvm_phase phase);
    item_t item;

    // Wait for reset to de-assert before driving
    @(posedge vif.clk iff vif.resetn);
    @(vif.master_cb);

    forever begin
      seq_item_port.get_next_item(item);
      `uvm_info("DRV", item.convert2string(), UVM_MEDIUM)

      case (item.mode)
        TXN_WRITE: drive_write(item);
        TXN_READ:  drive_read(item);
        TXN_BOTH:  drive_both(item);
        default:   `uvm_error("DRV", "Unknown transaction mode")
      endcase

      seq_item_port.item_done();
    end
  endtask

  // --------------------------------------------------------------------------
  // drive_write: AW + W channels in parallel, then B handshake
  // (carried over from driver.sv unchanged)
  // --------------------------------------------------------------------------
  task automatic drive_write(item_t item);
    fork
      drive_aw(item);
      drive_w(item);
    join
    drive_b(item);
  endtask

  // ---------- AW channel ----------
  task automatic drive_aw(item_t item);
    int delay = $urandom_range(0, max_aw_delay);
    repeat (delay) @(vif.master_cb);

    vif.master_cb.awvalid <= 1'b1;
    vif.master_cb.awaddr  <= item.addr;
    vif.master_cb.awprot  <= item.prot;

    @(vif.master_cb iff vif.master_cb.awready);
    vif.master_cb.awvalid <= 1'b0;
    vif.master_cb.awaddr  <= '0;
  endtask

  // ---------- W channel ----------
  task automatic drive_w(item_t item);
    int delay = $urandom_range(0, max_w_delay);
    repeat (delay) @(vif.master_cb);

    vif.master_cb.wvalid <= 1'b1;
    vif.master_cb.wdata  <= item.wdata;
    vif.master_cb.wstrb  <= item.wstrb;

    @(vif.master_cb iff vif.master_cb.wready);
    vif.master_cb.wvalid <= 1'b0;
    vif.master_cb.wdata  <= '0;
    vif.master_cb.wstrb  <= '0;
  endtask

  // ---------- B channel ----------
  task automatic drive_b(item_t item);
    int delay = $urandom_range(0, max_b_delay);
    repeat (delay) @(vif.master_cb);

    vif.master_cb.bready <= 1'b1;
    @(vif.master_cb iff vif.master_cb.bvalid);
    vif.master_cb.bready <= 1'b0;
  endtask

  // --------------------------------------------------------------------------
  // drive_read: AR channel then R channel
  // (carried over from driver.sv unchanged)
  // --------------------------------------------------------------------------
  task automatic drive_read(item_t item);
    int delay;

    delay = $urandom_range(0, max_ar_delay);
    repeat (delay) @(vif.master_cb);

    vif.master_cb.arvalid <= 1'b1;
    vif.master_cb.araddr  <= item.addr;
    vif.master_cb.arprot  <= item.prot;

    @(vif.master_cb iff vif.master_cb.arready);
    vif.master_cb.arvalid <= 1'b0;
    vif.master_cb.araddr  <= '0;

    delay = $urandom_range(0, max_r_delay);
    repeat (delay) @(vif.master_cb);

    vif.master_cb.rready <= 1'b1;
    @(vif.master_cb iff vif.master_cb.rvalid);
    vif.master_cb.rready <= 1'b0;
  endtask

  // --------------------------------------------------------------------------
  // drive_both: simultaneous AW + W + AR on the same clock edge
  // (carried over from driver.sv unchanged)
  // --------------------------------------------------------------------------
  task automatic drive_both(item_t item);
    int aw_delay, w_delay, ar_delay, max_delay;

    aw_delay  = $urandom_range(0, max_aw_delay);
    w_delay   = $urandom_range(0, max_w_delay);
    ar_delay  = $urandom_range(0, max_ar_delay);
    max_delay = (aw_delay > w_delay)   ? aw_delay  : w_delay;
    max_delay = (max_delay > ar_delay) ? max_delay : ar_delay;

    repeat (max_delay) @(vif.master_cb);

    vif.master_cb.awvalid <= 1'b1;
    vif.master_cb.awaddr  <= item.addr;
    vif.master_cb.awprot  <= item.prot;
    vif.master_cb.wvalid  <= 1'b1;
    vif.master_cb.wdata   <= item.wdata;
    vif.master_cb.wstrb   <= item.wstrb;
    vif.master_cb.arvalid <= 1'b1;
    vif.master_cb.araddr  <= item.addr;
    vif.master_cb.arprot  <= item.prot;

    @(vif.master_cb iff (vif.master_cb.awready &&
                         vif.master_cb.wready  &&
                         vif.master_cb.arready));

    vif.master_cb.awvalid <= 1'b0;
    vif.master_cb.awaddr  <= '0;
    vif.master_cb.wvalid  <= 1'b0;
    vif.master_cb.wdata   <= '0;
    vif.master_cb.wstrb   <= '0;
    vif.master_cb.arvalid <= 1'b0;
    vif.master_cb.araddr  <= '0;

    // B response first, then R response
    vif.master_cb.bready <= 1'b1;
    @(vif.master_cb iff vif.master_cb.bvalid);
    vif.master_cb.bready <= 1'b0;

    vif.master_cb.rready <= 1'b1;
    @(vif.master_cb iff vif.master_cb.rvalid);
    vif.master_cb.rready <= 1'b0;
  endtask

endclass

`endif // AXIL_DRIVER_SV
