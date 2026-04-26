// =============================================================================
// cov_iface.sv
// AXI4-Lite Functional Coverage — Cycle-Level / Protocol Coverage
//
// Module instantiated alongside the DUT and bound (by reference) to the
// axil_if interface. Samples covergroups every clock edge to capture
// protocol-level behaviour that cannot be observed at the transaction
// abstraction.
//
// Covergroups implemented (mapped to V-Plan FV-IDs):
//   FV-001    : cg_reset         — reset assertion / de-assertion
//   FV-002/003: cg_aw_w_hs       — AW vs W handshake ordering
//   FV-008    : cg_ar_hs         — AR handshake × RREADY delay
//   FV-011    : cg_fwd           — Same-cycle WR/RD same-address forwarding
//   FV-013    : cg_backpressure  — BREADY / RREADY stall cycles
//
// Together with coverage.sv (transaction-level), this implements all
// 11 covergroups specified in V-Plan Section 5.2.
//
// Usage:
//   In testbench_top.sv:
//     cov_iface u_cov_iface (
//       .clk    (clk),
//       .resetn (resetn),
//       .vif    (dut_if)
//     );
// =============================================================================

`ifndef AXI_COV_IFACE_SV
`define AXI_COV_IFACE_SV

module cov_iface #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
)(
  input logic clk,
  input logic resetn,
  axil_if vif
);

  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
  localparam int unsigned WORD_BITS  = $clog2(STRB_WIDTH);
  localparam int unsigned MEM_AW     = $clog2(MEM_DEPTH);

  // --------------------------------------------------------------------------
  // Local sampled signals (set by the always_ff trackers below)
  // --------------------------------------------------------------------------
  logic              prev_resetn = 1'b0;
  logic              reset_asserted_event;
  logic              reset_released_event;

  // AW vs W ordering tracker
  // 0 = idle, 1 = AW captured first, 2 = W captured first, 3 = concurrent
  logic [1:0]        aw_w_order;
  logic              aw_w_pair_done;

  // BREADY / RREADY backpressure: count cycles BVALID / RVALID held high
  int unsigned       bready_stall_cnt;
  int unsigned       rready_stall_cnt;
  logic              b_done_event;
  logic              r_done_event;

  // AR -> R latency: count cycles between AR handshake and R handshake
  int unsigned       ar_r_latency_cnt;
  logic              ar_active;
  logic              ar_r_done_event;

  // Write-before-read forwarding
  logic              fwd_event;
  logic [MEM_AW-1:0] fwd_word;

  // --------------------------------------------------------------------------
  // Reset edge detection
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    prev_resetn          <= resetn;
    reset_asserted_event <= prev_resetn  && !resetn;
    reset_released_event <= !prev_resetn &&  resetn;
  end

  // --------------------------------------------------------------------------
  // AW/W handshake ordering tracker
  //   Capture which of AW or W handshakes first (or concurrently), then mark
  //   the pair as "done" when the second one completes.
  // --------------------------------------------------------------------------
  logic aw_hs, w_hs;
  assign aw_hs = vif.awvalid && vif.awready;
  assign w_hs  = vif.wvalid  && vif.wready;

  logic awaiting_w_after_aw;
  logic awaiting_aw_after_w;

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      aw_w_order          <= 2'd0;
      aw_w_pair_done      <= 1'b0;
      awaiting_w_after_aw <= 1'b0;
      awaiting_aw_after_w <= 1'b0;
    end else begin
      aw_w_pair_done <= 1'b0;
      if (aw_hs && w_hs) begin
        // Concurrent
        aw_w_order     <= 2'd3;
        aw_w_pair_done <= 1'b1;
        awaiting_w_after_aw <= 1'b0;
        awaiting_aw_after_w <= 1'b0;
      end else if (aw_hs) begin
        if (awaiting_aw_after_w) begin
          aw_w_order          <= 2'd2;  // W came first
          aw_w_pair_done      <= 1'b1;
          awaiting_aw_after_w <= 1'b0;
        end else begin
          awaiting_w_after_aw <= 1'b1;
        end
      end else if (w_hs) begin
        if (awaiting_w_after_aw) begin
          aw_w_order          <= 2'd1;  // AW came first
          aw_w_pair_done      <= 1'b1;
          awaiting_w_after_aw <= 1'b0;
        end else begin
          awaiting_aw_after_w <= 1'b1;
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // BREADY backpressure: count BVALID-high cycles awaiting BREADY
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      bready_stall_cnt <= 0;
      b_done_event     <= 1'b0;
    end else begin
      b_done_event <= 1'b0;
      if (vif.bvalid && !vif.bready) begin
        bready_stall_cnt <= bready_stall_cnt + 1;
      end else if (vif.bvalid && vif.bready) begin
        b_done_event     <= 1'b1;
      end else begin
        bready_stall_cnt <= 0;
      end
    end
  end

  // --------------------------------------------------------------------------
  // RREADY backpressure: count RVALID-high cycles awaiting RREADY
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      rready_stall_cnt <= 0;
      r_done_event     <= 1'b0;
    end else begin
      r_done_event <= 1'b0;
      if (vif.rvalid && !vif.rready) begin
        rready_stall_cnt <= rready_stall_cnt + 1;
      end else if (vif.rvalid && vif.rready) begin
        r_done_event     <= 1'b1;
      end else begin
        rready_stall_cnt <= 0;
      end
    end
  end

  // --------------------------------------------------------------------------
  // AR -> R latency tracker
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      ar_active        <= 1'b0;
      ar_r_latency_cnt <= 0;
      ar_r_done_event  <= 1'b0;
    end else begin
      ar_r_done_event <= 1'b0;
      if (vif.arvalid && vif.arready) begin
        ar_active        <= 1'b1;
        ar_r_latency_cnt <= 0;
      end else if (ar_active) begin
        ar_r_latency_cnt <= ar_r_latency_cnt + 1;
        if (vif.rvalid && vif.rready) begin
          ar_active       <= 1'b0;
          ar_r_done_event <= 1'b1;
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // Write-before-read forwarding detector
  //   Same-cycle AW handshake and AR handshake to the same word address.
  // --------------------------------------------------------------------------
  logic [MEM_AW-1:0] aw_word, ar_word;
  assign aw_word = vif.awaddr[MEM_AW + WORD_BITS - 1 : WORD_BITS];
  assign ar_word = vif.araddr[MEM_AW + WORD_BITS - 1 : WORD_BITS];

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      fwd_event <= 1'b0;
      fwd_word  <= '0;
    end else begin
      fwd_event <= 1'b0;
      if (aw_hs && (vif.arvalid && vif.arready) && (aw_word == ar_word)) begin
        fwd_event <= 1'b1;
        fwd_word  <= aw_word;
      end
    end
  end

  // ==========================================================================
  // Covergroup: cg_reset (FV-001)
  // ==========================================================================
  covergroup cg_reset @(posedge clk);
    option.per_instance = 1;
    option.name         = "cg_reset";
    RST_EVENT: coverpoint {reset_asserted_event, reset_released_event} {
      bins reset_asserted = {2'b10};
      bins reset_released = {2'b01};
      bins steady_state   = {2'b00};
      illegal_bins both   = {2'b11};
    }
  endgroup

  // ==========================================================================
  // Covergroup: cg_aw_w_hs (FV-002 / FV-003)
  // ==========================================================================
  covergroup cg_aw_w_hs @(posedge clk iff aw_w_pair_done);
    option.per_instance = 1;
    option.name         = "cg_aw_w_hs";
    AW_W_ORDER: coverpoint aw_w_order {
      bins aw_first   = {2'd1};
      bins w_first    = {2'd2};
      bins concurrent = {2'd3};
      ignore_bins idle = {2'd0};
    }
  endgroup

  // ==========================================================================
  // Covergroup: cg_ar_hs (FV-008)
  //   AR handshake completion latency in cycles (binned).
  // ==========================================================================
  covergroup cg_ar_hs @(posedge clk iff ar_r_done_event);
    option.per_instance = 1;
    option.name         = "cg_ar_hs";
    AR_R_LATENCY: coverpoint ar_r_latency_cnt {
      bins lat_1_cycle    = {1};
      bins lat_2_cycle    = {2};
      bins lat_3_cycle    = {3};
      bins lat_4_to_7     = {[4:7]};
      bins lat_8_to_15    = {[8:15]};
      bins lat_long       = {[16:$]};
    }
  endgroup

  // ==========================================================================
  // Covergroup: cg_fwd (FV-011)
  //   Same-cycle write+read to same word address detected.
  // ==========================================================================
  covergroup cg_fwd @(posedge clk iff fwd_event);
    option.per_instance = 1;
    option.name         = "cg_fwd";
    FWD_HIT: coverpoint fwd_event {
      bins fwd_detected = {1};
    }
    FWD_ADDR: coverpoint fwd_word;
  endgroup

  // ==========================================================================
  // Covergroup: cg_backpressure (FV-013)
  //   Stall-cycle bins for BREADY and RREADY.
  // ==========================================================================
  covergroup cg_backpressure_b @(posedge clk iff b_done_event);
    option.per_instance = 1;
    option.name         = "cg_backpressure_b";
    B_STALL: coverpoint bready_stall_cnt {
      bins no_stall    = {0};
      bins stall_1_3   = {[1:3]};
      bins stall_4_7   = {[4:7]};
      bins stall_8_15  = {[8:15]};
      bins stall_long  = {[16:$]};
    }
  endgroup

  covergroup cg_backpressure_r @(posedge clk iff r_done_event);
    option.per_instance = 1;
    option.name         = "cg_backpressure_r";
    R_STALL: coverpoint rready_stall_cnt {
      bins no_stall    = {0};
      bins stall_1_3   = {[1:3]};
      bins stall_4_7   = {[4:7]};
      bins stall_8_15  = {[8:15]};
      bins stall_long  = {[16:$]};
    }
  endgroup

  // --------------------------------------------------------------------------
  // Instantiate covergroups
  // --------------------------------------------------------------------------
  cg_reset            cg_reset_i;
  cg_aw_w_hs          cg_aw_w_hs_i;
  cg_ar_hs            cg_ar_hs_i;
  cg_fwd              cg_fwd_i;
  cg_backpressure_b   cg_bp_b_i;
  cg_backpressure_r   cg_bp_r_i;

  initial begin
    cg_reset_i   = new();
    cg_aw_w_hs_i = new();
    cg_ar_hs_i   = new();
    cg_fwd_i     = new();
    cg_bp_b_i    = new();
    cg_bp_r_i    = new();
  end

  // --------------------------------------------------------------------------
  // End-of-sim coverage report (called from final block)
  // --------------------------------------------------------------------------
  final begin
    $display("======================================================");
    $display("[COV-IF] FUNCTIONAL COVERAGE REPORT (Cycle-Level)");
    $display("------------------------------------------------------");
    $display("  cg_reset          (FV-001)        : %5.2f %%", cg_reset_i.get_inst_coverage());
    $display("  cg_aw_w_hs        (FV-002/003)    : %5.2f %%", cg_aw_w_hs_i.get_inst_coverage());
    $display("  cg_ar_hs          (FV-008)        : %5.2f %%", cg_ar_hs_i.get_inst_coverage());
    $display("  cg_fwd            (FV-011)        : %5.2f %%", cg_fwd_i.get_inst_coverage());
    $display("  cg_backpressure_b (FV-013 / B)    : %5.2f %%", cg_bp_b_i.get_inst_coverage());
    $display("  cg_backpressure_r (FV-013 / R)    : %5.2f %%", cg_bp_r_i.get_inst_coverage());
    $display("======================================================");
  end

endmodule

`endif // AXI_COV_IFACE_SV
