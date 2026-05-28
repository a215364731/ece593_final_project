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
// axil_error_catcher — mirrors every UVM_ERROR and UVM_FATAL into a dedicated
// errors.log file, independent of UVM's file-routing precedence.
// =============================================================================
class axil_error_catcher extends uvm_report_catcher;
  int err_fd;

  function new(string name = "axil_error_catcher");
    super.new(name);
  endfunction

  function void set_file(int fd);
    err_fd = fd;
  endfunction

  virtual function action_e catch();
    uvm_severity sev = get_severity();
    if ((sev == UVM_ERROR || sev == UVM_FATAL) && err_fd != 0) begin
      $fdisplay(err_fd, "%s [%s] %s", sev.name(), get_id(), get_message());
    end
    return THROW;
  endfunction
endclass

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
  // UVM logging — file handles
  // --------------------------------------------------------------------------
  int log_fd;          // master log: everything
  int log_fd_drv;      // driver-only      ([DRV])
  int log_fd_mon;      // monitor-only     ([MON])
  int log_fd_scb;      // scoreboard-only  ([SCB])
  int log_fd_err;      // errors and fatals only
  axil_error_catcher err_catcher;

  function new(string name = "axil_test", uvm_component parent);
    super.new(name, parent);
    `uvm_info("TEST", "axil_test created", UVM_HIGH)
  endfunction

  // --------------------------------------------------------------------------
  // print_banner — ASCII banner shown at startup
  // --------------------------------------------------------------------------
  virtual function void print_banner();
    string seed_str;
    int    seed_val;
    if (!$value$plusargs("ntb_random_seed=%d", seed_val))
      seed_val = 0;
    seed_str = $sformatf("%0d", seed_val);

    $display("");
    $display("=================================================================");
    $display("");
    $display("           ECE-593  Pre-Si Validation Project                    ");
    $display("           AXI4-Lite Slave IP - UVM Testbench                    ");
    $display("");
    $display("           Portland State University - Spring 2026               ");
    $display("           Team1: Patrick  +  Pratibha                           ");
    $display("");
    $display("           Test  : %-20s                                ", get_type_name());
    $display("           Seed  : %-20s                                ", seed_str);
    $display("           Time  : %0t                                  ", $time);
    $display("");
    $display("=================================================================");
    $display("");
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
  // start_of_simulation_phase — banner + multi-file UVM logging
  // --------------------------------------------------------------------------
  virtual function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);

    print_banner();

    // Master log
    log_fd = $fopen("logs/axil_uvm.log", "w");
    if (log_fd == 0)
      `uvm_fatal("LOG", "Failed to open logs/axil_uvm.log for writing")
    set_report_default_file_hier(log_fd);
    set_report_severity_action_hier(UVM_INFO,    UVM_DISPLAY | UVM_LOG);
    set_report_severity_action_hier(UVM_WARNING, UVM_DISPLAY | UVM_LOG);
    set_report_severity_action_hier(UVM_ERROR,   UVM_DISPLAY | UVM_LOG | UVM_COUNT);
    set_report_severity_action_hier(UVM_FATAL,   UVM_DISPLAY | UVM_LOG | UVM_EXIT);

    // Per-component logs (routed by report-ID)
    log_fd_drv = $fopen("logs/driver.log",     "w");
    log_fd_mon = $fopen("logs/monitor.log",    "w");
    log_fd_scb = $fopen("logs/scoreboard.log", "w");
    if (log_fd_drv == 0 || log_fd_mon == 0 || log_fd_scb == 0)
      `uvm_fatal("LOG", "Failed to open one of the per-component log files")
    set_report_id_file_hier("DRV", log_fd_drv);
    set_report_id_file_hier("MON", log_fd_mon);
    set_report_id_file_hier("SCB", log_fd_scb);

    // Errors-only log via report catcher (sees every message regardless of routing)
    log_fd_err = $fopen("logs/errors.log", "w");
    if (log_fd_err == 0)
      `uvm_fatal("LOG", "Failed to open logs/errors.log for writing")
    err_catcher = new("axil_error_catcher");
    err_catcher.set_file(log_fd_err);
    uvm_report_cb::add(null, err_catcher);

    `uvm_info("LOG", "UVM logging enabled:", UVM_NONE)
    `uvm_info("LOG", "  master    -> logs/axil_uvm.log",   UVM_NONE)
    `uvm_info("LOG", "  driver    -> logs/driver.log",     UVM_NONE)
    `uvm_info("LOG", "  monitor   -> logs/monitor.log",    UVM_NONE)
    `uvm_info("LOG", "  scoreboard-> logs/scoreboard.log", UVM_NONE)
    `uvm_info("LOG", "  errors    -> logs/errors.log",     UVM_NONE)
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
    if (log_fd     != 0) begin $fclose(log_fd);     log_fd     = 0; end
    if (log_fd_drv != 0) begin $fclose(log_fd_drv); log_fd_drv = 0; end
    if (log_fd_mon != 0) begin $fclose(log_fd_mon); log_fd_mon = 0; end
    if (log_fd_scb != 0) begin $fclose(log_fd_scb); log_fd_scb = 0; end
    if (log_fd_err != 0) begin $fclose(log_fd_err); log_fd_err = 0; end
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
