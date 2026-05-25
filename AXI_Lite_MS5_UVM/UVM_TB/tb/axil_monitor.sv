// =============================================================================
// axil_monitor.sv
// AXI4-Lite UVM Monitor  (replaces monitor.sv)
//
// Migration notes:
//   - Extends uvm_monitor instead of plain class
//   - run_phase() wraps the existing fork/join_none block
//   - mon2scb mailboxes replaced by two uvm_analysis_port
//   - Virtual interface retrieved from uvm_config_db in build_phase()
//   - All five internal tasks carry over unchanged:
//       monitor_aw, monitor_w, merge_write, monitor_read, cycle_coverage
//   - All covergroups and sample() calls are unchanged
//   - report() moved to report_phase() called automatically by UVM
// =============================================================================

`ifndef AXIL_MONITOR_SV
`define AXIL_MONITOR_SV

`include "axil_seq_item.sv"

class axil_monitor #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
) extends uvm_monitor;

  typedef axil_seq_item #(DATA_WIDTH, ADDR_WIDTH) item_t;

  `uvm_component_param_utils(axil_monitor #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH))

  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
  localparam int unsigned WORD_BITS  = (STRB_WIDTH > 1) ? $clog2(STRB_WIDTH) : 1;

  // --------------------------------------------------------------------------
  // Virtual interface — set in testbench_top via uvm_config_db
  // --------------------------------------------------------------------------
  virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif;

  // --------------------------------------------------------------------------
  // Analysis ports — replace mon2scb_wr / mon2scb_rd mailboxes
  // --------------------------------------------------------------------------
  uvm_analysis_port #(item_t) monitor_port;

  // --------------------------------------------------------------------------
  // Internal staging mailboxes (AW and W may arrive in different cycles)
  // Unchanged from monitor.sv
  // --------------------------------------------------------------------------
  local mailbox #(item_t) aw_mbx;
  local mailbox #(item_t) w_mbx;

  // ==========================================================================
  // FUNCTIONAL COVERAGE — Cycle-Level  (carried over unchanged)
  // ==========================================================================
  bit          cov_reset_asserted = 0;
  bit          cov_reset_released = 0;
  bit [1:0]    cov_aw_w_order     = 0;
  int unsigned cov_ar_r_latency   = 0;
  int unsigned cov_b_stall_cnt    = 0;
  int unsigned cov_r_stall_cnt    = 0;
  bit          cov_fwd_event      = 0;

  covergroup cg_reset;
    option.per_instance = 1;
    option.name         = "cg_reset";
    RST_ASSERT: coverpoint vif.resetn {
      bins asserted   = {0};
      bins deasserted = {1};
    }
  endgroup

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

  covergroup cg_ar_hs;
    option.per_instance = 1;
    option.name         = "cg_ar_hs";
    AR_R_LATENCY: coverpoint cov_ar_r_latency {
      // Lowest latency is 3 cycles
      bins lat_3_cycle = {3};
      bins lat_4_to_7  = {[4:7]};
      bins lat_8_to_15 = {[8:15]};
      bins lat_long    = {[16:$]};
    }
  endgroup

  covergroup cg_fwd;
    option.per_instance = 1;
    option.name         = "cg_fwd";
    FWD_HIT: coverpoint cov_fwd_event {
      bins fwd_detected = {1};
    }
  endgroup

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
  function new(string name, uvm_component parent);
    super.new(name, parent);
    aw_mbx = new();
    w_mbx  = new();
    cg_reset   = new();
    cg_aw_w_hs = new();
    cg_ar_hs   = new();
    cg_fwd     = new();
    cg_bp_b    = new();
    cg_bp_r    = new();
    `uvm_info("MON", "axil_monitor created", UVM_HIGH)
  endfunction

  // --------------------------------------------------------------------------
  // build_phase — fetch vif and create analysis ports
  // --------------------------------------------------------------------------
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axil_if #(DATA_WIDTH, ADDR_WIDTH))::get(
          this, "", "vif", vif))
      `uvm_fatal("CFG", "axil_monitor: vif not found in uvm_config_db")

    monitor_port = new("monitor_port", this);
  endfunction

  // --------------------------------------------------------------------------
  // run_phase — launches all monitor threads (replaces run())
  // --------------------------------------------------------------------------
  virtual task run_phase(uvm_phase phase);
    fork
      monitor_aw();
      monitor_w();
      merge_write();
      monitor_read();
      cycle_coverage();
    join_none
  endtask

  // --------------------------------------------------------------------------
  // monitor_aw  (unchanged from monitor.sv)
  // --------------------------------------------------------------------------
  local task monitor_aw();
    forever begin
      @(vif.monitor_cb iff (vif.monitor_cb.awvalid && vif.monitor_cb.awready));
      begin
        item_t t = item_t::type_id::create("aw_item");
        t.mode = TXN_WRITE;
        t.addr = vif.monitor_cb.awaddr;
        t.prot = vif.monitor_cb.awprot;
        aw_mbx.put(t);
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // monitor_w  (unchanged from monitor.sv)
  // --------------------------------------------------------------------------
  local task monitor_w();
    forever begin
      @(vif.monitor_cb iff (vif.monitor_cb.wvalid && vif.monitor_cb.wready));
      begin
        item_t t = item_t::type_id::create("w_item");
        t.mode  = TXN_WRITE;
        t.wdata = vif.monitor_cb.wdata;
        t.wstrb = vif.monitor_cb.wstrb;
        w_mbx.put(t);
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // merge_write — pair AW + W, wait for B, write to analysis port
  // --------------------------------------------------------------------------
  local task merge_write();
    item_t aw_item, w_item, merged;
    forever begin
      aw_mbx.get(aw_item);
      w_mbx.get(w_item);

      merged       = item_t::type_id::create("merged_wr");
      merged.mode  = TXN_WRITE;
      merged.addr  = aw_item.addr;
      merged.prot  = aw_item.prot;
      merged.wdata = w_item.wdata;
      merged.wstrb = w_item.wstrb;

      @(vif.monitor_cb iff (vif.monitor_cb.bvalid && vif.monitor_cb.bready));
      merged.bresp = vif.monitor_cb.bresp;

      `uvm_info("MON", merged.convert2string(), UVM_MEDIUM)
      monitor_port.write(merged);   // replaces mon2scb_wr.put()
    end
  endtask

  // --------------------------------------------------------------------------
  // monitor_read — capture AR + R pair, write to analysis port
  // --------------------------------------------------------------------------
  local task monitor_read();
    item_t t;
    forever begin
      t = item_t::type_id::create("rd_item");
      t.mode = TXN_READ;

      @(vif.monitor_cb iff (vif.monitor_cb.arvalid && vif.monitor_cb.arready));
      t.addr = vif.monitor_cb.araddr;
      t.prot = vif.monitor_cb.arprot;

      @(vif.monitor_cb iff (vif.monitor_cb.rvalid && vif.monitor_cb.rready));
      t.rdata = vif.monitor_cb.rdata;
      t.rresp = vif.monitor_cb.rresp;

      `uvm_info("MON", t.convert2string(), UVM_MEDIUM)
      monitor_port.write(t);         // replaces mon2scb_rd.put()
    end
  endtask

  // --------------------------------------------------------------------------
  // cycle_coverage  (carried over unchanged from monitor.sv)
  // --------------------------------------------------------------------------
  local task cycle_coverage();
    bit          prev_resetn       = 1;
    bit          awaiting_w_after_aw = 0;
    bit          awaiting_aw_after_w = 0;
    int unsigned ar_r_cnt          = 0;
    bit          ar_active         = 0;
    int unsigned b_stall           = 0;
    int unsigned r_stall           = 0;

    forever begin
      @(posedge vif.clk);
      cg_reset.sample();
      if (!vif.resetn) begin
        awaiting_w_after_aw = 0;
        awaiting_aw_after_w = 0;
        ar_active = 0;
        ar_r_cnt  = 0;
        b_stall   = 0;
        r_stall   = 0;
        continue;
      end

      // AW vs W handshake ordering
      begin
        bit aw_hs = vif.monitor_cb.awvalid && vif.monitor_cb.awready;
        bit w_hs  = vif.monitor_cb.wvalid  && vif.monitor_cb.wready;

        if (aw_hs && w_hs) begin
          cov_aw_w_order = 2'd3;
          cg_aw_w_hs.sample();
          awaiting_w_after_aw = 0;
          awaiting_aw_after_w = 0;
        end else if (aw_hs) begin
          if (awaiting_aw_after_w) begin
            cov_aw_w_order = 2'd2;
            cg_aw_w_hs.sample();
            awaiting_aw_after_w = 0;
          end else begin
            awaiting_w_after_aw = 1;
          end
        end else if (w_hs) begin
          if (awaiting_w_after_aw) begin
            cov_aw_w_order = 2'd1;
            cg_aw_w_hs.sample();
            awaiting_w_after_aw = 0;
          end else begin
            awaiting_aw_after_w = 1;
          end
        end
      end

      // AR -> R latency tracking
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

      // BREADY backpressure
      begin
        if (vif.monitor_cb.bvalid && !vif.monitor_cb.bready)
          b_stall = b_stall + 1;
        else if (vif.monitor_cb.bvalid && vif.monitor_cb.bready) begin
          cov_b_stall_cnt = b_stall;
          cg_bp_b.sample();
          b_stall = 0;
        end
      end

      // RREADY backpressure
      begin
        if (vif.monitor_cb.rvalid && !vif.monitor_cb.rready)
          r_stall = r_stall + 1;
        else if (vif.monitor_cb.rvalid && vif.monitor_cb.rready) begin
          cov_r_stall_cnt = r_stall;
          cg_bp_r.sample();
          r_stall = 0;
        end
      end

      // Write-before-read forwarding detection
      begin
        bit aw_hs = vif.monitor_cb.awvalid && vif.monitor_cb.awready;
        bit ar_hs = vif.monitor_cb.arvalid && vif.monitor_cb.arready;

        if (aw_hs && ar_hs) begin
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
  // report_phase — replaces report(); called automatically by UVM
  // --------------------------------------------------------------------------
  virtual function void report_phase(uvm_phase phase);
    real avg_pct;
    avg_pct = (cg_reset.get_inst_coverage()
             + cg_aw_w_hs.get_inst_coverage()
             + cg_ar_hs.get_inst_coverage()
             + cg_fwd.get_inst_coverage()
             + cg_bp_b.get_inst_coverage()
             + cg_bp_r.get_inst_coverage()) / 6.0;

    `uvm_info("MON", "======================================================", UVM_NONE)
    `uvm_info("MON", "FUNCTIONAL COVERAGE (Cycle-Level)", UVM_NONE)
    `uvm_info("MON", $sformatf("  cg_reset       (FV-001)     : %6.2f %%", cg_reset.get_inst_coverage()),    UVM_NONE)
    `uvm_info("MON", $sformatf("  cg_aw_w_hs     (FV-002/003) : %6.2f %%", cg_aw_w_hs.get_inst_coverage()),  UVM_NONE)
    `uvm_info("MON", $sformatf("  cg_ar_hs       (FV-008)     : %6.2f %%", cg_ar_hs.get_inst_coverage()),    UVM_NONE)
    `uvm_info("MON", $sformatf("  cg_fwd         (FV-011)     : %6.2f %%", cg_fwd.get_inst_coverage()),      UVM_NONE)
    `uvm_info("MON", $sformatf("  cg_bp_b        (FV-013/B)   : %6.2f %%", cg_bp_b.get_inst_coverage()),     UVM_NONE)
    `uvm_info("MON", $sformatf("  cg_bp_r        (FV-013/R)   : %6.2f %%", cg_bp_r.get_inst_coverage()),     UVM_NONE)
    `uvm_info("MON", $sformatf("  Avg (cycle-level)           : %6.2f %%", avg_pct),                         UVM_NONE)
    `uvm_info("MON", "======================================================", UVM_NONE)
  endfunction

endclass

`endif // AXIL_MONITOR_SV
