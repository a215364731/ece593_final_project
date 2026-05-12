// =============================================================================
// axil_if.sv
// AXI4-Lite Interface
//
// Bundles all AXI4-Lite signals into a single interface for clean
// connectivity between the DUT and testbench components.
// =============================================================================

`ifndef AXI_IF_SV
`define AXI_IF_SV

interface axil_if #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12
)(
  input logic clk
);

  // resetn is driven by the master (driver), not an input
  logic resetn;

  // Write Address Channel (AW)
  logic                      awvalid;
  logic                      awready;
  logic [ADDR_WIDTH-1:0]     awaddr;
  logic [2:0]                awprot;

  // Write Data Channel (W)
  logic                      wvalid;
  logic                      wready;
  logic [DATA_WIDTH-1:0]     wdata;
  logic [(DATA_WIDTH/8)-1:0] wstrb;

  // Write Response Channel (B)
  logic                      bvalid;
  logic                      bready;
  logic [1:0]                bresp;

  // Read Address Channel (AR)
  logic                      arvalid;
  logic                      arready;
  logic [ADDR_WIDTH-1:0]     araddr;
  logic [2:0]                arprot;

  // Read Data Channel (R)
  logic                      rvalid;
  logic                      rready;
  logic [DATA_WIDTH-1:0]     rdata;
  logic [1:0]                rresp;


  // Master (driver) clocking block — drives stimulus to DUT
  clocking master_cb @(posedge clk);
    default input #1step output #1;

    // Reset (driven by master)
    output resetn;

    // AW
    output awvalid, awaddr, awprot;
    input  awready;

    // W
    output wvalid, wdata, wstrb;
    input  wready;

    // B
    input  bvalid, bresp;
    output bready;

    // AR
    output arvalid, araddr, arprot;
    input  arready;

    // R
    input  rvalid, rdata, rresp;
    output rready;
  endclocking

  // Monitor clocking block — observes both sides
  clocking monitor_cb @(posedge clk);
    default input #1step;

    input resetn;
    input awvalid, awready, awaddr, awprot;
    input wvalid,  wready,  wdata,  wstrb;
    input bvalid,  bready,  bresp;
    input arvalid, arready, araddr, arprot;
    input rvalid,  rready,  rdata,  rresp;
  endclocking

  // --------------------------------------------------------------------------
  // Modports
  // --------------------------------------------------------------------------
  modport MASTER  (clocking master_cb,  input clk);
  modport MONITOR (clocking monitor_cb, input clk);

  // --------------------------------------------------------------------------
  // Reset task - asserts and deasserts resetn, clears all signals
  // --------------------------------------------------------------------------
  task automatic do_reset();
    // Assert reset
    master_cb.resetn <= 1'b0;
    repeat (10) @(posedge clk);
    
    // Clear all signals
    master_cb.awvalid <= '0;
    master_cb.awaddr  <= '0;
    master_cb.awprot  <= '0;
    master_cb.wvalid  <= '0;
    master_cb.wdata   <= '0;
    master_cb.wstrb   <= '0;
    master_cb.bready  <= '0;
    master_cb.arvalid <= '0;
    master_cb.araddr  <= '0;
    master_cb.arprot  <= '0;
    master_cb.rready  <= '0;
    
    // Release reset
    master_cb.resetn <= 1'b1;
    repeat (5) @(posedge clk);
  endtask

endinterface

`endif // AXI_IF_SV
