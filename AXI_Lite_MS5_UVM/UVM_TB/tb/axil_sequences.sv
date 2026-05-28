// =============================================================================
// axil_sequences.sv
// AXI4-Lite UVM Sequences  (replaces generator.sv)
//
// Migration notes:
//   - generator class is replaced by a library of uvm_sequence classes
//   - mailbox.put() replaced by start_item() / finish_item()
//   - add_write / add_read / add_both helpers moved into dedicated sequences
//   - axil_base_seq       : base class with shared helpers
//   - axil_random_seq     : fully random write/read mix (replaces test_random)
//   - axil_wr_rd_seq      : directed write-then-read (replaces test_wr_rd_same)
//   - axil_byte_strobe_seq: directed byte-strobe test (replaces test_byte_strobe)
//   - axil_concurrent_seq : directed TXN_BOTH test    (replaces test_concurrent_rw)
// =============================================================================

`ifndef AXIL_SEQUENCES_SV
`define AXIL_SEQUENCES_SV

`include "axil_seq_item.sv"

// =============================================================================
// axil_base_seq — shared helpers for all sequences
// =============================================================================
class axil_base_seq #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
) extends uvm_sequence #(axil_seq_item #(DATA_WIDTH, ADDR_WIDTH));

  typedef axil_seq_item #(DATA_WIDTH, ADDR_WIDTH) item_t;

  `uvm_object_param_utils(axil_base_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH))

  function new(string name = "axil_base_seq");
    super.new(name);
  endfunction

  // --------------------------------------------------------------------------
  // Helper: send a directed write
  // --------------------------------------------------------------------------
  protected task send_write(
    logic [ADDR_WIDTH-1:0]     addr,
    logic [DATA_WIDTH-1:0]     data,
    logic [(DATA_WIDTH/8)-1:0] strb = '1,
    logic [2:0]                prot = '0,
    int constraint_mode = 1
  );
    item_t item = item_t::type_id::create("wr_item");
    start_item(item);
    if(constraint_mode == 0) begin
      item.c_addr_align.constraint_mode(0);
    end
    if (!item.randomize() with {
      mode  == TXN_WRITE;
      addr  == local::addr;
      wdata == local::data;
      wstrb == local::strb;
      prot  == local::prot;
    }) `uvm_fatal("SEQ", "Randomize failed for directed write")
    finish_item(item);
  endtask

  // --------------------------------------------------------------------------
  // Helper: send a directed read
  // --------------------------------------------------------------------------
  protected task send_read(
    logic [ADDR_WIDTH-1:0] addr,
    logic [2:0]            prot = '0,
    int constraint_mode = 1
  );
    item_t item = item_t::type_id::create("rd_item");
    start_item(item);
    if(constraint_mode == 0) begin
      item.c_addr_align.constraint_mode(0);
    end
    if (!item.randomize() with {
      mode == TXN_READ;
      addr == local::addr;
      prot == local::prot;
    }) `uvm_fatal("SEQ", "Randomize failed for directed read")
    finish_item(item);
  endtask

  // --------------------------------------------------------------------------
  // Helper: send a directed concurrent read+write (TXN_BOTH)
  // --------------------------------------------------------------------------
  protected task send_both(
    logic [ADDR_WIDTH-1:0]     addr,
    logic [DATA_WIDTH-1:0]     wdata,
    logic [(DATA_WIDTH/8)-1:0] strb = '1,
    logic [2:0]                prot = '0
  );
    item_t item = item_t::type_id::create("both_item");
    start_item(item);
    // Must disable c_mode_random to allow TXN_BOTH
    item.c_mode_random.constraint_mode(0);
    if (!item.randomize() with {
      mode  == TXN_BOTH;
      addr  == local::addr;
      wdata == local::wdata;
      wstrb == local::strb;
      prot  == local::prot;
    }) `uvm_fatal("SEQ", "Randomize failed for directed both")
    finish_item(item);
  endtask

  protected task send_both_diff(
    logic [ADDR_WIDTH-1:0]     addr,
    logic [DATA_WIDTH-1:0]     wdata,
    logic [(DATA_WIDTH/8)-1:0] strb = '1,
    logic [2:0]                prot = '0
  );
    item_t item = item_t::type_id::create("both_item");
    start_item(item);
    // Must disable c_mode_random to allow TXN_BOTH
    item.c_mode_random.constraint_mode(0);
    if (!item.randomize() with {
      mode  == TXN_BOTH_DIFF;
      addr  == local::addr;
      wdata == local::wdata;
      wstrb == local::strb;
      prot  == local::prot;
    }) `uvm_fatal("SEQ", "Randomize failed for directed both, different addr")
    finish_item(item);
  endtask

  // --------------------------------------------------------------------------
  // Helper: word-aligned random address within MEM_DEPTH
  // --------------------------------------------------------------------------
  protected function logic [ADDR_WIDTH-1:0] rand_mem_addr();
    int unsigned word_idx = $urandom_range(0, MEM_DEPTH - 1);
    return ADDR_WIDTH'(word_idx * (DATA_WIDTH / 8));
  endfunction

endclass

// =============================================================================
// axil_random_seq — fully random write/read mix
// Replaces: test_random (directed_phase was empty, 50 random txns)
// =============================================================================
class axil_random_seq #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
) extends axil_base_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH);

  typedef axil_seq_item #(DATA_WIDTH, ADDR_WIDTH) item_t;

  `uvm_object_param_utils(axil_random_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH))

  int unsigned num_transactions = 50;

  function new(string name = "axil_random_seq");
    super.new(name);
  endfunction

  virtual task body();
    item_t item;
    repeat (num_transactions) begin
      item = item_t::type_id::create("rand_item");
      start_item(item);
      // Constrain address to valid memory window
      if (!item.randomize() with {
        addr == rand_mem_addr();
      }) `uvm_fatal("SEQ", "Randomize failed")
      finish_item(item);
    end
    `uvm_info("SEQ", $sformatf("axil_random_seq: sent %0d random transactions",
              num_transactions), UVM_MEDIUM)
  endtask

endclass

// =============================================================================
// axil_wr_rd_seq — write then read back same addresses
// Replaces: test_wr_rd_same directed_phase()
// =============================================================================
class axil_wr_rd_seq #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
) extends axil_base_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH);

  `uvm_object_param_utils(axil_wr_rd_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH))

  localparam int unsigned N   = 8;
  localparam int unsigned BPW = DATA_WIDTH / 8;

  function new(string name = "axil_wr_rd_seq");
    super.new(name);
  endfunction

  virtual task body();
    // Write phase
    for (int i = 0; i < N; i++)
      send_write(ADDR_WIDTH'(i * BPW), DATA_WIDTH'(32'hDEAD_0000 | i), '1);
    // Read phase (same addresses)
    for (int i = 0; i < N; i++)
      send_read(ADDR_WIDTH'(i * BPW));
    `uvm_info("SEQ", $sformatf("axil_wr_rd_seq: %0d writes + %0d reads", N, N), UVM_MEDIUM)
  endtask

endclass

// =============================================================================
// axil_byte_strobe_seq — partial byte-lane write verification
// Replaces: test_byte_strobe directed_phase()
// =============================================================================
class axil_byte_strobe_seq #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
) extends axil_base_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH);

  `uvm_object_param_utils(axil_byte_strobe_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH))

  function new(string name = "axil_byte_strobe_seq");
    super.new(name);
  endfunction

  virtual task body();
    // Write full word then overwrite each byte lane individually
    send_write(12'h000, 32'hAABBCCDD, 4'b1111);
    send_write(12'h000, 32'h12000000, 4'b1000);
    send_write(12'h000, 32'h00340000, 4'b0100);
    send_write(12'h000, 32'h00005600, 4'b0010);
    send_write(12'h000, 32'h00000078, 4'b0001);
    // Read back: expect 0x12345678
    send_read(12'h000);
    for(int i = 1; i < 16; i++) begin
      send_write(12'h000, 32'h87654321, i);
      send_read(12'h000);
    end
    `uvm_info("SEQ", "axil_byte_strobe_seq: all strobe types", UVM_MEDIUM)
  endtask

endclass

// =============================================================================
// axil_concurrent_seq — simultaneous read+write (TXN_BOTH)
// Replaces: test_concurrent_rw directed_phase()
// =============================================================================
class axil_concurrent_seq #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
) extends axil_base_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH);

  `uvm_object_param_utils(axil_concurrent_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH))

  localparam int unsigned N   = 6;
  localparam int unsigned BPW = DATA_WIDTH / 8;

  function new(string name = "axil_concurrent_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int i = 0; i < N; i++)
      send_both(ADDR_WIDTH'(i * BPW), DATA_WIDTH'(32'hCCCC_0000 | i), '1);

    send_both(12'h000, 32'hAAAA5555, 4'b1100);
    send_both(12'h000, 32'h5555AAAA, 4'b0011);
    send_both(12'h004, 32'hDEADBEEF, 4'b1111);

    send_both_diff(12'h008, 32'hDEADBEEF, 4'b1111);
    send_both_diff(12'h010, 32'hDEADBEEF, 4'b1111);
    `uvm_info("SEQ", $sformatf("axil_concurrent_seq: %0d TXN_BOTH transactions", N + 5), UVM_MEDIUM)
  endtask

endclass

// =============================================================================
// axil_addr_oor_seq — Write to an out of range address and expect an error response
// =============================================================================
class axil_addr_oor_seq #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
) extends axil_base_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH);

  `uvm_object_param_utils(axil_addr_oor_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH))

  function new(string name = "axil_addr_oor_seq");
    super.new(name);
  endfunction

  virtual task body();
    send_write(ADDR_WIDTH'(MEM_DEPTH * (DATA_WIDTH/8)+ 4), 32'hDEAD_BEEF, '1);
    send_read(ADDR_WIDTH'(MEM_DEPTH * (DATA_WIDTH/8)+ 4));
    send_write(12'hff0, 32'hDEAD_BEEF, '1);
    send_read(12'hff0);

    `uvm_info("SEQ", $sformatf("axil_addr_oor_seq: Address out of range"), UVM_MEDIUM)
  endtask

endclass

// =============================================================================
// axil_unaligned_rd_wr_seq — Unaligned address test (should be rejected by the DUT)
// =============================================================================
class axil_unaligned_rd_wr_seq #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
) extends axil_base_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH);

  `uvm_object_param_utils(axil_unaligned_rd_wr_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH))

  localparam int unsigned N   = 8;
  localparam int unsigned BPW = DATA_WIDTH / 8;

  function new(string name = "axil_unaligned_rd_wr_seq");
    super.new(name);
  endfunction

  virtual task body();
    send_write(12'h001, 32'hAABBCCDD, 4'b1111,0,0);
    send_write(12'h002, 32'h11223344, 4'b1111,0,0);
    send_write(12'h003, 32'h55667788, 4'b1111,0,0);

    send_read(12'h001,0,0);
    send_read(12'h002,0,0);
    send_read(12'h003,0,0);

    `uvm_info("SEQ", $sformatf("axil_unaligned_rd_wr_seq: "), UVM_MEDIUM)
  endtask

endclass


`endif // AXIL_SEQUENCES_SV
