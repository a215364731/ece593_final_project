// =============================================================================
// transaction.sv
// AXI4-Lite Transaction Object
//
// Represents a single AXI4-Lite read or write transaction.
// Used by the generator, driver, monitor, and scoreboard.
// =============================================================================

`ifndef AXI_TRANSACTION_SV
`define AXI_TRANSACTION_SV

typedef enum logic [1:0] { TXN_WRITE, TXN_READ, TXN_BOTH } txn_mode;

class transaction #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12
);

  // --------------------------------------------------------------------------
  // Transaction fields
  // --------------------------------------------------------------------------
  rand txn_mode         mode;
  rand logic [ADDR_WIDTH-1:0]  addr;
  rand logic [DATA_WIDTH-1:0]  wdata;
  rand logic [(DATA_WIDTH/8)-1:0] wstrb;
  rand logic [2:0]             prot;

  // Populated by the monitor on the response side
  logic [DATA_WIDTH-1:0]       rdata;
  logic [1:0]                  bresp;
  logic [1:0]                  rresp;


  // --------------------------------------------------------------------------
  // Constraints
  // --------------------------------------------------------------------------

  // Byte-aligned, word-aligned address
  constraint c_addr_align {
    addr[1:0] == 2'b00;            // 32-bit word align
    addr < (1 << ADDR_WIDTH);
  }

  // At least one strobe bit active on writes and read+writes
  constraint c_wstrb_nonzero {
    (mode == TXN_WRITE || mode == TXN_BOTH) -> wstrb != '0;
  }

  // Random transactions use only WRITE or READ (not BOTH)
  constraint c_mode_random {
    mode inside { TXN_WRITE, TXN_READ };
  }

  // --------------------------------------------------------------------------
  // Utilities
  // --------------------------------------------------------------------------
  function void print(string tag = "");
    if(mode == TXN_READ) begin
      $display("[%s] READ | addr=0x%0h | rdata=0x%0h | rresp=%0b | prot=%0b",
              tag,
              addr, rdata, rresp, prot);
    end
    if(mode == TXN_WRITE) begin
      $display("[%s] WRITE | addr=0x%0h | wdata=0x%0h | wstrb=0b%0b | bresp=%0b | prot=%0b",
              tag,
              addr, wdata, wstrb, bresp, prot);
    end
    if(mode == TXN_BOTH) begin
      $display("[%s] READ+WRITE | addr=0x%0h | wdata=0x%0h | wstrb=0b%0b | rdata=0x%0h | bresp=%0b | rresp=%0b | prot=%0b",
              tag,
              addr, wdata, wstrb, rdata, bresp, rresp, prot);
    end
  endfunction

endclass

`endif // AXI_TRANSACTION_SV
