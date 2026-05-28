// =============================================================================
// axil_tb_top.sv
// AXI4-Lite UVM Testbench Top  (replaces testbench_top.sv)
//
// Migration notes:
//   - Static instantiation of clock, interface, and DUT is unchanged
//   - Sequential test execution block removed ? run_test() dispatches
//     whichever test is selected via +UVM_TESTNAME on the command line
//   - Virtual interface pushed into uvm_config_db once, available to all
//     components through the hierarchy
//   - Reset is applied before run_test() so the DUT is in a known state
//     when the first sequence starts; tests no longer call do_reset()
//   - `include chain: only axil_tb_top needs to include axil_tests.sv;
//     each file guards itself with `ifndef / `define
//
// Compile and run example (VCS):
//   vcs -sverilog -ntb_opts uvm-1.2 \
//       axil_if.sv axil_tb_top.sv s_axil_top.v \
//       +incdir+. -timescale=1ns/1ps
//   ./simv +UVM_TESTNAME=axil_test_random
//   ./simv +UVM_TESTNAME=axil_test_wr_rd_same
//   ./simv +UVM_TESTNAME=axil_test_byte_strobe
//   ./simv +UVM_TESTNAME=axil_test_concurrent_rw
// =============================================================================

`timescale 1ns/1ps

`include "axil_if.sv"        // unchanged from original ? interface, clocking blocks, do_reset()


module axil_tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "axil_seq_item.sv"
  `include "axil_sequences.sv"  
  `include "axil_sequencer.sv"
  `include "axil_driver.sv"     
  `include "axil_monitor.sv"    
  `include "axil_scoreboard.sv" 
  `include "axil_env.sv"        
  `include "axil_tests.sv" 

  // --------------------------------------------------------------------------
  // Parameters ? match the DUT
  // --------------------------------------------------------------------------
  localparam int unsigned DATA_WIDTH = 32;
  localparam int unsigned ADDR_WIDTH = 12;
  localparam int unsigned MEM_DEPTH  = 256;
  // MEM_INIT can be overridden at compile time with +define+MEM_INIT_EMPTY
  // to exercise the "no initialization" else-branches on s_axil_top.sv:73,80
  // (coverage closure). Used by the `make compile_no_init` target.
`ifdef MEM_INIT_EMPTY
  localparam string       MEM_INIT   = "";
`else
  localparam string       MEM_INIT   = "./tb/mem_init.hex";
`endif

  // --------------------------------------------------------------------------
  // Clock generation  (unchanged from testbench_top.sv)
  // --------------------------------------------------------------------------
  logic clk;
  initial clk = 0;
  always #5 clk = ~clk;   // 100 MHz

  // --------------------------------------------------------------------------
  // Interface and DUT  (unchanged from testbench_top.sv)
  // --------------------------------------------------------------------------
  axil_if #(DATA_WIDTH, ADDR_WIDTH) axil_bus (.clk(clk));

  s_axil_top #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .MEM_DEPTH  (MEM_DEPTH),
    .MEM_INIT   (MEM_INIT)
  ) dut (
    .clk        (clk),
    .resetn     (axil_bus.resetn),
    .s_axi_awvalid    (axil_bus.awvalid),
    .s_axi_awready    (axil_bus.awready),
    .s_axi_awaddr     (axil_bus.awaddr),
    .s_axi_awprot     (axil_bus.awprot),
    .s_axi_wvalid     (axil_bus.wvalid),
    .s_axi_wready     (axil_bus.wready),
    .s_axi_wdata      (axil_bus.wdata),
    .s_axi_wstrb      (axil_bus.wstrb),
    .s_axi_bvalid     (axil_bus.bvalid),
    .s_axi_bready     (axil_bus.bready),
    .s_axi_bresp      (axil_bus.bresp),
    .s_axi_arvalid    (axil_bus.arvalid),
    .s_axi_arready    (axil_bus.arready),
    .s_axi_araddr     (axil_bus.araddr),
    .s_axi_arprot     (axil_bus.arprot),
    .s_axi_rvalid     (axil_bus.rvalid),
    .s_axi_rready     (axil_bus.rready),
    .s_axi_rdata      (axil_bus.rdata),
    .s_axi_rresp      (axil_bus.rresp)
  );

  // --------------------------------------------------------------------------
  // UVM config DB ? push the virtual interface so all components can get it
  // --------------------------------------------------------------------------
  initial begin
    uvm_config_db #(virtual axil_if #(DATA_WIDTH, ADDR_WIDTH))::set(
      null, "uvm_test_top.*", "vif", axil_bus);

    // Optional: push mem_init path to the scoreboard
    uvm_config_db #(string)::set(
      null, "uvm_test_top.*", "mem_init", MEM_INIT);
  end


  // --------------------------------------------------------------------------
  // UVM entry point ? test selected via +UVM_TESTNAME plusarg
  // --------------------------------------------------------------------------
  initial begin
    run_test("axil_test"); 
  end

endmodule
