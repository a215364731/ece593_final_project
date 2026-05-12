// =============================================================================
// axil_sequencer.sv
// AXI4-Lite UVM Sequencer
//
// Thin wrapper around uvm_sequencer parameterized on axil_seq_item.
// No additional functionality is added; this class exists to complete
// the standard UVM component set and to allow future extension
// (e.g. p_sequencer access, custom arbitration, config handle).
// =============================================================================

`ifndef AXIL_SEQUENCER_SV
`define AXIL_SEQUENCER_SV

`include "axil_seq_item.sv"

class axil_sequencer #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12
) extends uvm_sequencer #(axil_seq_item #(DATA_WIDTH, ADDR_WIDTH));

  `uvm_component_param_utils(axil_sequencer #(DATA_WIDTH, ADDR_WIDTH))

  function new(string name, uvm_component parent);
    super.new(name, parent);
    `uvm_info("SEQ", "axil_sequencer created", UVM_HIGH)
  endfunction

endclass

`endif // AXIL_SEQUENCER_SV