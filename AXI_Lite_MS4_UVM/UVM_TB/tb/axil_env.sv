// =============================================================================
// axil_env.sv
// AXI4-Lite UVM Environment  (replaces env.sv)
//
// Migration notes:
//   - Extends uvm_env instead of plain class
//   - Generator, driver, and mailboxes replaced by axil_agent (which
//     internally holds driver + sequencer + monitor)
//   - Scoreboard wired to monitor via analysis ports in connect_phase()
//   - drain() / stop() removed — UVM phase objections control simulation end
//   - report() removed — report_phase() in scoreboard and monitor run automatically
//   - vif is set once in testbench_top; config_db propagates it to all children
// =============================================================================

`ifndef AXIL_ENV_SV
`define AXIL_ENV_SV

`include "axil_agent.sv"
`include "axil_scoreboard.sv"

class axil_env #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
) extends uvm_env;

  typedef axil_seq_item #(DATA_WIDTH, ADDR_WIDTH) item_t;

  `uvm_component_param_utils(axil_env #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH))

  // --------------------------------------------------------------------------
  // Sub-components
  // --------------------------------------------------------------------------
  axil_agent      #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH) agent;
  axil_scoreboard #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH) scoreboard;

  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    `uvm_info("ENV", "axil_env created", UVM_HIGH)
  endfunction

  // --------------------------------------------------------------------------
  // build_phase — instantiate agent and scoreboard
  // --------------------------------------------------------------------------
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent      = axil_agent      #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)::type_id::create("agent",      this);
    scoreboard = axil_scoreboard #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)::type_id::create("scoreboard", this);
  endfunction

  // --------------------------------------------------------------------------
  // connect_phase — wire monitor analysis ports to scoreboard imp ports
  // --------------------------------------------------------------------------
  virtual function void connect_phase(uvm_phase phase);
    agent.monitor_port.connect(scoreboard.analysis_imp);
  endfunction

endclass

`endif // AXIL_ENV_SV
