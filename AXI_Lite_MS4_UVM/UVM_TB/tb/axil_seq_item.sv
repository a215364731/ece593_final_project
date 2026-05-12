// =============================================================================
// axil_seq_item.sv
// AXI4-Lite UVM Sequence Item  (replaces transaction.sv)
//
// Migration notes:
//   - Extends uvm_sequence_item instead of a plain class
//   - Fields registered with `uvm_field_* macros for automation
//   - print() replaced by UVM do_print() / `uvm_object_utils automation
//   - Constraints are unchanged
// =============================================================================

`ifndef AXIL_SEQ_ITEM_SV
`define AXIL_SEQ_ITEM_SV


typedef enum logic [1:0] { TXN_WRITE, TXN_READ, TXN_BOTH } txn_mode_e;

class axil_seq_item #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12
) extends uvm_sequence_item;

  // --------------------------------------------------------------------------
  // UVM factory registration
  // --------------------------------------------------------------------------
  `uvm_object_param_utils_begin(axil_seq_item #(DATA_WIDTH, ADDR_WIDTH))
    `uvm_field_enum(txn_mode_e,       mode,  UVM_ALL_ON)
    `uvm_field_int (addr,                    UVM_ALL_ON | UVM_HEX)
    `uvm_field_int (wdata,                   UVM_ALL_ON | UVM_HEX)
    `uvm_field_int (wstrb,                   UVM_ALL_ON | UVM_BIN)
    `uvm_field_int (prot,                    UVM_ALL_ON | UVM_BIN)
    `uvm_field_int (rdata,                   UVM_ALL_ON | UVM_HEX)
    `uvm_field_int (bresp,                   UVM_ALL_ON | UVM_BIN)
    `uvm_field_int (rresp,                   UVM_ALL_ON | UVM_BIN)
  `uvm_object_utils_end

  // --------------------------------------------------------------------------
  // Transaction fields
  // --------------------------------------------------------------------------
  rand txn_mode_e                      mode;
  rand logic [ADDR_WIDTH-1:0]          addr;
  rand logic [DATA_WIDTH-1:0]          wdata;
  rand logic [(DATA_WIDTH/8)-1:0]      wstrb;
  rand logic [2:0]                     prot;

  // Populated by the monitor on the response side
  logic [DATA_WIDTH-1:0]               rdata;
  logic [1:0]                          bresp;
  logic [1:0]                          rresp;

  // --------------------------------------------------------------------------
  // Constraints  (unchanged from transaction.sv)
  // --------------------------------------------------------------------------

  // 32-bit word-aligned address, within the address space
  constraint c_addr_align {
    addr[1:0] == 2'b00;
    addr < (1 << ADDR_WIDTH);
  }

  // At least one strobe bit active on writes and concurrent transactions
  constraint c_wstrb_nonzero {
    (mode == TXN_WRITE || mode == TXN_BOTH) -> wstrb != '0;
  }

  // Random transactions use only WRITE or READ (not BOTH)
  // Override or disable this constraint in sequences that need TXN_BOTH
  constraint c_mode_random {
    mode inside { TXN_WRITE, TXN_READ };
  }

  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(string name = "axil_seq_item");
    super.new(name);
  endfunction

  function is_write();
    return mode == TXN_WRITE;
  endfunction

  function is_read();
    return mode == TXN_READ;
  endfunction

  // --------------------------------------------------------------------------
  // convert2string  — used by UVM logging (`uvm_info with .convert2string())
  // --------------------------------------------------------------------------
  virtual function string convert2string();
    string s;
    case (mode)
      TXN_WRITE: s = $sformatf(
        "WRITE addr=0x%0h wdata=0x%0h wstrb=0b%0b bresp=%0b prot=%0b",
        addr, wdata, wstrb, bresp, prot);
      TXN_READ:  s = $sformatf(
        "READ  addr=0x%0h rdata=0x%0h rresp=%0b prot=%0b",
        addr, rdata, rresp, prot);
      TXN_BOTH:  s = $sformatf(
        "BOTH  addr=0x%0h wdata=0x%0h wstrb=0b%0b rdata=0x%0h bresp=%0b rresp=%0b prot=%0b",
        addr, wdata, wstrb, rdata, bresp, rresp, prot);
      default:   s = "UNKNOWN";
    endcase
    return s;
  endfunction

endclass

`endif // AXIL_SEQ_ITEM_SV
