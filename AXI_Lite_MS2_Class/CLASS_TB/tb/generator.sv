// =============================================================================
// generator.sv
// AXI4-Lite Transaction Generator
//
// Produces a stream of randomized transaction objects and places them
// into a mailbox for the driver to consume.  Supports:
//   - Fully random transactions
//   - Directed sequences injected via directed_txn_q
//   - Configurable transaction count and seed
// =============================================================================

`ifndef AXI_GENERATOR_SV
`define AXI_GENERATOR_SV

`include "transaction.sv"

class generator #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
);

  typedef transaction #(DATA_WIDTH, ADDR_WIDTH) txn_t;

  // --------------------------------------------------------------------------
  // Configuration
  // --------------------------------------------------------------------------
  int unsigned num_transactions = 20;    // How many random transactions to send
  int unsigned seed             = 0;     // Random seed (0 = use SV default)
  bit          verbose          = 1;     // Print each generated transaction

  // --------------------------------------------------------------------------
  // Mailbox to driver
  // --------------------------------------------------------------------------
  mailbox #(txn_t) gen2drv;

  // --------------------------------------------------------------------------
  // Directed transaction queue
  // Populated by the test before calling run().
  // Directed transactions are sent FIRST, then random ones follow.
  // --------------------------------------------------------------------------
  txn_t directed_txn_q[$];

  // --------------------------------------------------------------------------
  // Internals
  // --------------------------------------------------------------------------
  local int unsigned txn_count = 0;

  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(mailbox #(txn_t) mbx);
    gen2drv = mbx;
  endfunction

  // --------------------------------------------------------------------------
  // Helper: constrain address to valid memory range
  // --------------------------------------------------------------------------
  local function logic [ADDR_WIDTH-1:0] rand_mem_addr();
    // word-aligned address within MEM_DEPTH words
    int unsigned word_idx = $urandom_range(0, MEM_DEPTH - 1);
    return ADDR_WIDTH'(word_idx * (DATA_WIDTH / 8));
  endfunction

  // --------------------------------------------------------------------------
  // run() - called from the environment
  // --------------------------------------------------------------------------
  task run();
    txn_t txn;

    if (seed != 0) $srandom(seed);

    // ---- Directed transactions first ----
    foreach (directed_txn_q[i]) begin
      txn_count++;
      if (verbose) directed_txn_q[i].print("GEN-DIRECTED");
      gen2drv.put(directed_txn_q[i]);
    end

    // ---- Random transactions ----
    repeat (num_transactions) begin
      txn = new();
      // Override address constraint to stay in valid memory window
      txn.addr = rand_mem_addr();
      if (!txn.randomize() with { addr == local::txn.addr; }) begin
        $fatal(1, "[GEN] Randomization failed!");
      end
      txn_count++;
      if (verbose) txn.print("GEN-RAND");
      gen2drv.put(txn);
    end

    $display("[GEN] Done. Generated %0d transactions (%0d directed + %0d random).",
             txn_count, directed_txn_q.size(), num_transactions);
  endtask

  // --------------------------------------------------------------------------
  // Convenience: queue a directed write
  // --------------------------------------------------------------------------
  function void add_write(
    logic [ADDR_WIDTH-1:0]      addr,
    logic [DATA_WIDTH-1:0]      data,
    logic [(DATA_WIDTH/8)-1:0]  strb = '1,
    logic [2:0]                 prot = '0
  );
    txn_t t = new();
    t.mode  = TXN_WRITE;
    t.addr  = addr;
    t.wdata = data;
    t.wstrb = strb;
    t.prot  = prot;
    directed_txn_q.push_back(t);
  endfunction

  // --------------------------------------------------------------------------
  // Convenience: queue a directed read
  // --------------------------------------------------------------------------
  function void add_read(
    logic [ADDR_WIDTH-1:0] addr,
    logic [2:0]            prot = '0
  );
    txn_t t = new();
    t.mode = TXN_READ;
    t.addr = addr;
    t.prot = prot;
    directed_txn_q.push_back(t);
  endfunction

endclass

`endif // AXI_GENERATOR_SV
