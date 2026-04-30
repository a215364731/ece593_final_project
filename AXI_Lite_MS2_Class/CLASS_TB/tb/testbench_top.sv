// =============================================================================
// testbench_top.sv
// AXI4-Lite Testbench Top Level
//
// Instantiates:
//   - axi_if  (interface)
//   - s_axil_top (DUT)
//   - Clock/reset generation
//
// Functional coverage is embedded in the testbench classes:
//   - Transaction-level covergroups: scoreboard.sv
//   - Cycle-level covergroups:       monitor.sv
// =============================================================================

`timescale 1ns / 1ps

`include "axil_if.sv"
`include "tests.sv"

module testbench_top;

  // --------------------------------------------------------------------------
  // Parameters - match DUT
  // --------------------------------------------------------------------------
  localparam int unsigned DATA_WIDTH = 32;
  localparam int unsigned ADDR_WIDTH = 12;
  localparam int unsigned MEM_DEPTH  = 2**(ADDR_WIDTH-2);
  localparam string       MEM_INIT   = "./tb/mem_init.hex";

  localparam real CLK_PERIOD_NS = 10.0;  // 100 MHz

  // --------------------------------------------------------------------------
  // Clock
  // --------------------------------------------------------------------------
  logic clk = 0;

  always #(CLK_PERIOD_NS / 2.0) clk = ~clk;

  // --------------------------------------------------------------------------
  // Interface
  // --------------------------------------------------------------------------
  axil_if #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .ADDR_WIDTH ( ADDR_WIDTH )
  ) dut_if (
    .clk ( clk )
  );

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  s_axil_top #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .ADDR_WIDTH ( ADDR_WIDTH ),
    .MEM_DEPTH  ( MEM_DEPTH  ),
    .MEM_INIT   ( MEM_INIT   )
  ) dut (
    .clk            ( clk                ),
    .resetn         ( dut_if.resetn      ),

    .s_axi_awvalid  ( dut_if.awvalid     ),
    .s_axi_awready  ( dut_if.awready     ),
    .s_axi_awaddr   ( dut_if.awaddr      ),
    .s_axi_awprot   ( dut_if.awprot      ),

    .s_axi_wvalid   ( dut_if.wvalid      ),
    .s_axi_wready   ( dut_if.wready      ),
    .s_axi_wdata    ( dut_if.wdata       ),
    .s_axi_wstrb    ( dut_if.wstrb       ),

    .s_axi_bvalid   ( dut_if.bvalid      ),
    .s_axi_bready   ( dut_if.bready      ),
    .s_axi_bresp    ( dut_if.bresp       ),

    .s_axi_arvalid  ( dut_if.arvalid     ),
    .s_axi_arready  ( dut_if.arready     ),
    .s_axi_araddr   ( dut_if.araddr      ),
    .s_axi_arprot   ( dut_if.arprot      ),

    .s_axi_rvalid   ( dut_if.rvalid      ),
    .s_axi_rready   ( dut_if.rready      ),
    .s_axi_rdata    ( dut_if.rdata       ),
    .s_axi_rresp    ( dut_if.rresp       )
  );

  // --------------------------------------------------------------------------
  // Test execution
  // --------------------------------------------------------------------------
  initial begin
    test_random       #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH, MEM_INIT) t1 = new(dut_if);
    test_wr_rd_same   #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH, MEM_INIT) t2 = new(dut_if);
    test_byte_strobe   #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH, MEM_INIT) t3 = new(dut_if);
    test_concurrent_rw #(DATA_WIDTH, ADDR_WIDTH, MEM_DEPTH, MEM_INIT) t4 = new(dut_if);

    // Wait for clock to start and interface to be ready
    @(posedge clk);
    @(posedge clk);

    t1.run();
    t2.run();
    t3.run();
    t4.run();

    $display("[TB] Test complete at time %0t ns.", $time);
    $finish;
  end

  initial begin
    $fsdbDumpvars();
  end

endmodule
