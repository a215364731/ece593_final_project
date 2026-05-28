// =============================================================================
// axil_tests.sv
// AXI4-Lite UVM Test Library
//
// Single unified test class that runs all test scenarios in sequence:
//   1. random_seq       : 50 fully random write/read transactions
//   2. wr_rd_seq        : directed write-then-read coherence check
//   3. byte_strobe_seq  : directed byte-lane masking verification
//   4. concurrent_seq   : directed TXN_BOTH simultaneous read+write
// =============================================================================

`ifndef AXIL_TESTS_SV
`define AXIL_TESTS_SV

`include "axil_env.sv"
`include "axil_sequences.sv"

// =============================================================================
// axil_test — unified test with sequences as properties
// =============================================================================
class axil_test extends uvm_test;

  typedef axil_seq_item #(DATA_WIDTH, ADDR_WIDTH) item_t;
    
  parameter int unsigned DATA_WIDTH = 32;
  parameter int unsigned ADDR_WIDTH = 12;
  parameter int unsigned MEM_DEPTH  = 256;

  `uvm_component_utils(axil_test)

  // --------------------------------------------------------------------------
  // Test environment
  // --------------------------------------------------------------------------
  axil_env #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH) env;

  // --------------------------------------------------------------------------
  // Sequence properties
  // --------------------------------------------------------------------------
  axil_random_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH) random_seq;
  axil_wr_rd_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH) wr_rd_seq;
  axil_byte_strobe_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH) byte_strobe_seq;
  axil_concurrent_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH) concurrent_seq;
  axil_addr_oor_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH) addr_oor_seq;
  axil_unaligned_rd_wr_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH) unaligned_rd_wr_seq;

  // --------------------------------------------------------------------------
  // UVM logging — file handle for the persistent log
  // --------------------------------------------------------------------------
  int log_fd;

  function new(string name = "axil_test", uvm_component parent);
    super.new(name, parent);
    `uvm_info("TEST", "axil_test created", UVM_HIGH)
  endfunction

  // --------------------------------------------------------------------------
  // build_phase — create env and sequences
  // --------------------------------------------------------------------------
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axil_env #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)::type_id::create("env", this);
    
    random_seq = axil_random_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)::type_id::create("random_seq");
    wr_rd_seq = axil_wr_rd_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)::type_id::create("wr_rd_seq");
    byte_strobe_seq = axil_byte_strobe_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)::type_id::create("byte_strobe_seq");
    concurrent_seq = axil_concurrent_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)::type_id::create("concurrent_seq");
    addr_oor_seq = axil_addr_oor_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)::type_id::create("addr_oor_seq");
    unaligned_rd_wr_seq = axil_unaligned_rd_wr_seq #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)::type_id::create("unaligned_rd_wr_seq");
  endfunction

  // --------------------------------------------------------------------------
  // start_of_simulation_phase — set up UVM logging
  //
  // Opens axil_uvm.log and routes every uvm_* message at this component and
  // below to BOTH the simulator transcript (UVM_DISPLAY) and the log file
  // (UVM_LOG). The `+UVM_LOG_FILE=<name>` plusarg can override this at run
  // time. The hier variants apply the setting to every child component, so
  // env / agent / driver / monitor / scoreboard all log automatically.
  // --------------------------------------------------------------------------
  virtual function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    log_fd = $fopen("logs/axil_uvm.log", "w");
    if (log_fd == 0)
      `uvm_fatal("LOG", "Failed to open axil_uvm.log for writing")
    set_report_default_file_hier(log_fd);
    set_report_severity_action_hier(UVM_INFO,    UVM_DISPLAY | UVM_LOG);
    set_report_severity_action_hier(UVM_WARNING, UVM_DISPLAY | UVM_LOG);
    set_report_severity_action_hier(UVM_ERROR,   UVM_DISPLAY | UVM_LOG | UVM_COUNT);
    set_report_severity_action_hier(UVM_FATAL,   UVM_DISPLAY | UVM_LOG | UVM_EXIT);
    `uvm_info("LOG", "UVM logging enabled: writing to axil_uvm.log", UVM_NONE)
  endfunction

  // --------------------------------------------------------------------------
  // end_of_elaboration_phase — print UVM topology
  // --------------------------------------------------------------------------
  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    
    `uvm_info("TEST", "Starting axil_test_random", UVM_MEDIUM)
    run_random_test();
    
    `uvm_info("TEST", "Starting axil_test_wr_rd_same", UVM_MEDIUM)
    run_wr_rd_test();
    
    `uvm_info("TEST", "Starting axil_test_byte_strobe", UVM_MEDIUM)
    run_byte_strobe_test();
    
    `uvm_info("TEST", "Starting axil_test_concurrent_rw", UVM_MEDIUM)
    run_concurrent_test();

    `uvm_info("TEST", "Starting axil_test_addr_oor", UVM_MEDIUM)
    run_addr_oor_test();

    `uvm_info("TEST", "Starting axil_test_unaligned_rd_wr", UVM_MEDIUM)
    run_unaligned_rd_wr_test();
    
    phase.drop_objection(this);
  endtask

  // --------------------------------------------------------------------------
  // final_phase — close the UVM log file
  // --------------------------------------------------------------------------
  virtual function void final_phase(uvm_phase phase);
    super.final_phase(phase);
    if (log_fd != 0) begin
      $fclose(log_fd);
      log_fd = 0;
    end
  endfunction

  // --------------------------------------------------------------------------
  // Test scenario tasks
  // --------------------------------------------------------------------------

  // Random test: 50 fully random write/read transactions
  virtual task run_random_test();
    random_seq.num_transactions = 1000;
    random_seq.start(env.agent.sequencer);
  endtask

  // Write-then-read coherence check
  virtual task run_wr_rd_test();
    wr_rd_seq.start(env.agent.sequencer);
  endtask

  // Byte-lane masking verification
  virtual task run_byte_strobe_test();
    byte_strobe_seq.start(env.agent.sequencer);
  endtask

  // Concurrent read+write test
  virtual task run_concurrent_test();
    concurrent_seq.start(env.agent.sequencer);
  endtask

  // Address out of range test
  virtual task run_addr_oor_test();
    addr_oor_seq.start(env.agent.sequencer);
  endtask

  virtual task run_unaligned_rd_wr_test();
    unaligned_rd_wr_seq.start(env.agent.sequencer);
  endtask

endclass

`endif // AXIL_TESTS_SV
