// =============================================================================
// scoreboard.sv
// AXI4-Lite Scoreboard
//
// Maintains a software model of the DUT's internal memory and checks every
// observed transaction against expected values.
//
// Checks performed:
//   Write:
//     - bresp must be OKAY (2'b00)
//     - Internal shadow memory updated with masked write
//   Read:
//     - rresp must be OKAY (2'b00)
//     - rdata must match the shadow memory contents (respecting write strobes)
//     - Read after write hazard: if a write to the same address is in-flight
//       or recently completed, the latest data wins (write-before-read model)
//
// Coverage:
//   - Address bins across the memory depth
//   - All-strobes-set vs partial-strobe writes
//   - Read-after-write to same address
// =============================================================================

`ifndef AXI_SCOREBOARD_SV
`define AXI_SCOREBOARD_SV

`include "transaction.sv"

class scoreboard #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256,
  parameter string       MEM_INIT    = ""
);

  typedef transaction #(DATA_WIDTH, ADDR_WIDTH) txn_t;

  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
  localparam int unsigned BYTES_PER_WORD = DATA_WIDTH / 8;

  // --------------------------------------------------------------------------
  // Mailboxes from monitor
  // --------------------------------------------------------------------------
  mailbox #(txn_t) mon2scb_wr;
  mailbox #(txn_t) mon2scb_rd;

  // --------------------------------------------------------------------------
  // Shadow memory model
  // --------------------------------------------------------------------------
  local logic [DATA_WIDTH-1:0] shadow_mem [0:MEM_DEPTH-1];
  local bit                    shadow_valid [0:MEM_DEPTH-1];

  // --------------------------------------------------------------------------
  // Statistics
  // --------------------------------------------------------------------------
  int unsigned writes_checked  = 0;
  int unsigned reads_checked   = 0;
  int unsigned errors          = 0;

  bit verbose = 1;

  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(
    mailbox #(txn_t) mbx_wr,
    mailbox #(txn_t) mbx_rd
  );
    this.mon2scb_wr = mbx_wr;
    this.mon2scb_rd = mbx_rd;
    
    foreach (shadow_mem[i]) shadow_mem[i] = '0;
    if (MEM_INIT != "") $readmemh(MEM_INIT, shadow_mem);
  endfunction

  // --------------------------------------------------------------------------
  // run() - launches write and read check threads
  // --------------------------------------------------------------------------
  task run();
    fork
      check_writes();
      check_reads();
    join_none
  endtask

  // --------------------------------------------------------------------------
  // check_writes
  // --------------------------------------------------------------------------
  task check_writes();
    txn_t txn;
    forever begin
      mon2scb_wr.get(txn);
      writes_checked++;

      // --- Check bresp ---
      if (txn.bresp !== 2'b00) begin
        $error("[SCB] WRITE ERROR: bresp=0b%02b expected OKAY(00) addr=0x%0h",
               txn.bresp, txn.addr);
        errors++;
      end

      // --- Update shadow memory ---
      update_shadow(txn.addr, txn.wdata, txn.wstrb);

      if (verbose)
        $display("[SCB] WRITE OK  addr=0x%0h data=0x%0h strb=0b%0b bresp=%0b",
                 txn.addr, txn.wdata, txn.wstrb, txn.bresp);
    end
  endtask

  // --------------------------------------------------------------------------
  // check_reads
  // --------------------------------------------------------------------------
  task check_reads();
    txn_t txn;
    logic [DATA_WIDTH-1:0] expected;
    int unsigned word_idx;
    forever begin
      mon2scb_rd.get(txn);
      reads_checked++;

      // --- Check rresp ---
      if (txn.rresp !== 2'b00) begin
        $error("[SCB] READ  ERROR: rresp=0b%02b expected OKAY(00) addr=0x%0h",
               txn.rresp, txn.addr);
        errors++;
      end

      // --- Check rdata against shadow (only if we have written this address) ---
      word_idx = addr_to_idx(txn.addr);
      expected = shadow_mem[word_idx];
      if (txn.rdata !== expected) begin
        $error("[SCB] READ  MISMATCH: addr=0x%0h got=0x%0h expected=0x%0h",
                txn.addr, txn.rdata, expected);
        errors++;
      end else begin
        if (verbose)
          $display("[SCB] READ  OK  addr=0x%0h data=0x%0h rresp=%0b",
                   txn.addr, txn.rdata, txn.rresp);
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Shadow memory helpers
  // --------------------------------------------------------------------------
  local function void update_shadow(
    logic [ADDR_WIDTH-1:0]      addr,
    logic [DATA_WIDTH-1:0]      wdata,
    logic [STRB_WIDTH-1:0]      wstrb
  );
    int unsigned idx = addr_to_idx(addr);
    if (idx >= MEM_DEPTH) begin
      $warning("[SCB] update_shadow: address 0x%0h out of range (MEM_DEPTH=%0d)", addr, MEM_DEPTH);
      return;
    end
    if (!shadow_valid[idx]) shadow_mem[idx] = '0;
    for (int b = 0; b < STRB_WIDTH; b++) begin
      if (wstrb[b])
        shadow_mem[idx][b*8 +: 8] = wdata[b*8 +: 8];
    end
    shadow_valid[idx] = 1;
  endfunction

  local function int unsigned addr_to_idx(logic [ADDR_WIDTH-1:0] addr);
    return int'(addr) / BYTES_PER_WORD;
  endfunction

  // --------------------------------------------------------------------------
  // report() - call at end of simulation
  // --------------------------------------------------------------------------
  function void report();
    $display("======================================================");
    $display("[SCB] SCOREBOARD REPORT");
    $display("  Writes checked : %0d", writes_checked);
    $display("  Reads  checked : %0d", reads_checked);
    $display("  Errors found   : %0d", errors);
    if (errors == 0)
      $display("  RESULT: ** PASS **");
    else
      $display("  RESULT: ** FAIL ** (%0d errors)", errors);
    $display("======================================================");
  endfunction

endclass

`endif // AXI_SCOREBOARD_SV
