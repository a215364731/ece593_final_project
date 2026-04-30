// =============================================================================
// tests.sv
// AXI4-Lite Test Library
//
// Defines a base test class plus several concrete tests:
//
//   test_base        - reset, build, run, drain, report lifecycle
//   test_random      - fully random read/write mix (default)
//   test_wr_rd_same  - directed: write then read back same addresses
//   test_byte_strobe - directed: partial byte-strobe write checks
//   test_backpressure - max delays on all channels
// =============================================================================

`ifndef AXI_TESTS_SV
`define AXI_TESTS_SV

`include "env.sv"

// =============================================================================
// test_base
// =============================================================================
class test_base #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256,
  parameter string       MEM_INIT    = ""
);

  typedef transaction #(DATA_WIDTH, ADDR_WIDTH) txn_t;

  env #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH, MEM_INIT) env;
  virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif;

  function new(virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif);
    this.vif = vif;
  endfunction

  // Override in derived tests to set env config before run
  virtual function void configure();
    env.num_transactions = 20;
    env.verbose          = 1;
  endfunction

  // Override to inject directed transactions
  virtual task directed_phase();
    // empty by default
  endtask

  task run();
    // Build
    env = new();
    env.vif = vif;
    configure();
    env.init();

    // Directed phase (before random)
    directed_phase();

    // Apply reset
    do_reset();

    // Start environment
    env.run();

    // Wait for completion
    env.drain();

    // Stop all component threads gracefully
    env.stop();

    // Report
    env.report();
  endtask

  task do_reset();
    $display("[TEST] Calling interface do_reset...");
    vif.do_reset();
    @(vif.master_cb);
    @(vif.master_cb);
    $display("[TEST] Reset complete.");
  endtask

endclass

// =============================================================================
// test_random
// Pure random test: default knobs, 50 transactions
// =============================================================================
class test_random #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256,
  parameter string       MEM_INIT    = ""
) extends test_base #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH, MEM_INIT);

  function new(virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif);
    super.new(vif);
  endfunction

  virtual function void configure();
    env.num_transactions = 50;
    env.verbose          = 1;
  endfunction

endclass

// =============================================================================
// test_wr_rd_same
// Directed: write known values to N addresses, then read each back.
// Verifies basic write-then-read coherence.
// =============================================================================
class test_wr_rd_same #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256,
  parameter string       MEM_INIT    = ""
) extends test_base #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH, MEM_INIT);

  localparam int unsigned N = 8;
  localparam int unsigned BPW = DATA_WIDTH / 8;

  function new(virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif);
    super.new(vif);
  endfunction

  virtual function void configure();
    env.num_transactions = 0;   // directed only
    env.verbose          = 1;
  endfunction

  virtual task directed_phase();
    // Write phase
    for (int i = 0; i < N; i++) begin
      logic [ADDR_WIDTH-1:0]  addr  = ADDR_WIDTH'(i * BPW);
      logic [DATA_WIDTH-1:0]  data  = DATA_WIDTH'(32'hDEAD_0000 | i);
      env.gen.add_write(addr, data, '1);
    end
    // Read phase (same addresses)
    for (int i = 0; i < N; i++) begin
      logic [ADDR_WIDTH-1:0] addr = ADDR_WIDTH'(i * BPW);
      env.gen.add_read(addr);
    end
    $display("[TEST] test_wr_rd_same: queued %0d writes + %0d reads",
             N, N);
  endtask

endclass

// =============================================================================
// test_byte_strobe
// Directed: write full word, then partial-strobe overwrite, then read back.
// Checks that the strobe masking in the DUT and shadow model agree.
// =============================================================================
class test_byte_strobe #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256,
  parameter string       MEM_INIT    = ""
) extends test_base #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH, MEM_INIT);

  function new(virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif);
    super.new(vif);
  endfunction

  virtual function void configure();
    env.num_transactions = 0;
    env.verbose          = 1;
  endfunction

  virtual task directed_phase();
    // Write 0xAABBCCDD to address 0 (all strobes)
    env.gen.add_write(12'h000, 32'hAABBCCDD, 4'b1111);
    env.gen.add_write(12'h000, 32'h12000000, 4'b1000);
    env.gen.add_write(12'h000, 32'h00340000, 4'b0100);
    env.gen.add_write(12'h000, 32'h00005600, 4'b0010);
    env.gen.add_write(12'h000, 32'h00000078, 4'b0001);
    // Read back: expect 0x12345678
    env.gen.add_read(12'h000);


    $display("[TEST] test_byte_strobe: queued 4 writes + 2 reads");
  endtask

endclass

// =============================================================================
// test_concurrent_rw
// Directed: simultaneous read and write transactions using TXN_BOTH mode.
// Tests concurrent AW/W/AR address channels and B/R response channels
// operating in parallel to verify proper arbitration and response handling.
// =============================================================================
class test_concurrent_rw #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256,
  parameter string       MEM_INIT    = ""
) extends test_base #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH, MEM_INIT);

  localparam int unsigned N = 6;
  localparam int unsigned BPW = DATA_WIDTH / 8;

  function new(virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif);
    super.new(vif);
  endfunction

  virtual function void configure();
    env.num_transactions = 0;   // directed only
    env.verbose          = 1;
  endfunction

  virtual task directed_phase();
    // Queue N simultaneous read+write transactions at different addresses
    // Each transaction writes a unique pattern then reads back from same address
    for (int i = 0; i < N; i++) begin
      logic [ADDR_WIDTH-1:0]  addr  = ADDR_WIDTH'(i * BPW);
      logic [DATA_WIDTH-1:0]  wdata = DATA_WIDTH'(32'hCCCC_0000 | i);
      env.gen.add_both(addr, wdata, '1);
    end

    // Additional pattern: write and read at same address with different strobes
    env.gen.add_both(12'h000, 32'hAAAA5555, 4'b1100);  // Upper bytes only
    env.gen.add_both(12'h000, 32'h5555AAAA, 4'b0011);  // Lower bytes only
    env.gen.add_both(12'h004, 32'hDEAD_BEEF, 4'b1111);  // Full word

    $display("[TEST] test_concurrent_rw: queued %0d simultaneous read+write transactions",
             N + 3);
  endtask

endclass


`endif // AXI_TESTS_SV
