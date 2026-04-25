// =============================================================================
// env.sv
// AXI4-Lite Verification Environment
//
// Instantiates and connects all testbench components:
//   - generator
//   - driver
//   - monitor
//   - scoreboard
//
// The environment owns all mailboxes.  The test only interacts with the
// environment (and through it, the generator's directed-txn queue).
//
// Lifecycle:
//   env.init()  - creates all components and mailboxes
//   env.run()    - forks generator, driver, monitor, scoreboard threads
//   env.drain()  - waits for all in-flight transactions to complete
//   env.report() - prints scoreboard summary and asserts pass/fail
// =============================================================================

`ifndef AXI_ENV_SV
`define AXI_ENV_SV

`include "transaction.sv"
`include "generator.sv"
`include "driver.sv"
`include "monitor.sv"
`include "scoreboard.sv"

class env #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256,
  parameter string       MEM_INIT    = ""
);

  typedef transaction #(DATA_WIDTH, ADDR_WIDTH) txn_t;

  // --------------------------------------------------------------------------
  // Components
  // --------------------------------------------------------------------------
  generator  #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)  gen;
  driver     #(DATA_WIDTH, ADDR_WIDTH)             drv;
  monitor    #(DATA_WIDTH, ADDR_WIDTH)             mon;
  scoreboard #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH, MEM_INIT)  scb;

  // --------------------------------------------------------------------------
  // Mailboxes
  // --------------------------------------------------------------------------
  mailbox #(txn_t) gen2drv;
  mailbox #(txn_t) mon2scb_wr;
  mailbox #(txn_t) mon2scb_rd;

  // --------------------------------------------------------------------------
  // Virtual interface (set by the test before build)
  // --------------------------------------------------------------------------
  virtual axil_if #(DATA_WIDTH, ADDR_WIDTH) vif;

  // --------------------------------------------------------------------------
  // Configuration pass-throughs (set before build or directly on components)
  // --------------------------------------------------------------------------
  int unsigned num_transactions = 20;
  bit          verbose          = 1;

  // --------------------------------------------------------------------------
  // init() - instantiate and wire everything
  // --------------------------------------------------------------------------
  function void init();
    // Mailboxes
    gen2drv    = new();
    mon2scb_wr = new();
    mon2scb_rd = new();

    // Components
    gen = new(gen2drv);
    drv = new(vif, gen2drv);
    mon = new(vif, mon2scb_wr, mon2scb_rd);
    scb = new(mon2scb_wr, mon2scb_rd);

    // Config
    gen.num_transactions = num_transactions;
    gen.verbose          = verbose;
    drv.verbose          = verbose;
    mon.verbose          = verbose;
    scb.verbose          = verbose;

    $display("[ENV] Init complete. num_transactions=%0d", num_transactions);
  endfunction

  // --------------------------------------------------------------------------
  // run() - fork all component threads
  // --------------------------------------------------------------------------
  task run();
    $display("[ENV] Starting run...");
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
    join_none
  endtask

  // --------------------------------------------------------------------------
  // drain() - wait until the generator is done AND the scoreboard has
  //           processed all expected transactions
  // --------------------------------------------------------------------------
  task drain(int unsigned timeout_cycles = 10000);
    int unsigned total_expected;
    int unsigned waited;

    total_expected = gen.directed_txn_q.size() + gen.num_transactions;

    // Poll until scoreboard has seen all transactions or timeout
    waited = 0;
    while ((scb.writes_checked + scb.reads_checked) < total_expected) begin
      @(posedge vif.clk);
      waited++;
      if (waited >= timeout_cycles) begin
        $error("[ENV] Drain timeout after %0d cycles! Checked %0d/%0d transactions.",
               timeout_cycles, scb.writes_checked + scb.reads_checked, total_expected);
        break;
      end
    end

    // A few extra cycles for final responses to propagate
    repeat (10) @(posedge vif.clk);
    $display("[ENV] Drain complete after %0d cycles.", waited);
  endtask

  // --------------------------------------------------------------------------
  // report()
  // --------------------------------------------------------------------------
  function void report();
    scb.report();
    if (scb.errors > 0)
      $fatal(1, "[ENV] Simulation FAILED with %0d scoreboard errors.", scb.errors);
    else
      $display("[ENV] Simulation PASSED.");
  endfunction

endclass

`endif // AXI_ENV_SV
