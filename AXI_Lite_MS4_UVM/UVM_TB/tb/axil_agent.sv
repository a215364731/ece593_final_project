// =============================================================================
// axil_agent.sv
// AXI4-Lite UVM Agent  (new file — split from env.sv)
//
// The agent owns the three active components:
//   - axil_driver     (BFM driving the DUT)
//   - uvm_sequencer   (manages sequence item flow to the driver)
//   - axil_monitor    (passively observes the bus)
//
// The generator + gen2drv mailbox from env.sv are fully replaced by
// the sequencer.  Tests start sequences on agent.sequencer.
//
// The agent exposes the monitor's two analysis ports for the env to
// connect to the scoreboard.
// =============================================================================

`ifndef AXIL_AGENT_SV
`define AXIL_AGENT_SV

`include "axil_seq_item.sv"
`include "axil_driver.sv"
`include "axil_monitor.sv"

class axil_agent #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
) extends uvm_agent;

  typedef axil_seq_item #(DATA_WIDTH, ADDR_WIDTH) item_t;

  `uvm_component_param_utils(axil_agent #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH))

  // --------------------------------------------------------------------------
  // Sub-components
  // --------------------------------------------------------------------------
  axil_driver    #(DATA_WIDTH, ADDR_WIDTH)           drv;
  axil_sequencer #(DATA_WIDTH, ADDR_WIDTH)           sequencer;
  axil_monitor   #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH) mon;

  // --------------------------------------------------------------------------
  // Analysis ports forwarded from the monitor for the env to connect
  // --------------------------------------------------------------------------
  uvm_analysis_port #(item_t) monitor_port;

  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    `uvm_info("AGT", "axil_agent created", UVM_HIGH)
  endfunction

  // --------------------------------------------------------------------------
  // build_phase — instantiate driver, sequencer, monitor
  // --------------------------------------------------------------------------
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // The virtual interface is set at the top level and propagates through
    // the config DB hierarchy automatically — no need to re-set here
    drv       = axil_driver   #(DATA_WIDTH, ADDR_WIDTH)::type_id::create("drv",       this);
    sequencer = axil_sequencer #(DATA_WIDTH, ADDR_WIDTH)::type_id::create("sequencer", this);
    mon       = axil_monitor  #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH)::type_id::create("mon", this);

    // Forwarded analysis ports (connected in connect_phase)
    monitor_port = new("monitor_port", this);
  endfunction

  // --------------------------------------------------------------------------
  // connect_phase — wire driver to sequencer; forward monitor analysis ports
  // --------------------------------------------------------------------------
  virtual function void connect_phase(uvm_phase phase);
    // Driver pulls items from the sequencer
    drv.seq_item_port.connect(sequencer.seq_item_export);

    // Forward monitor analysis ports up to the env level
    mon.monitor_port.connect(monitor_port);
  endfunction

endclass

`endif // AXIL_AGENT_SV
