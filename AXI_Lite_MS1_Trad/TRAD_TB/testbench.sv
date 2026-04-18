`timescale 1ns / 1ps

module testbench;

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------
  localparam int unsigned DATA_WIDTH  = 32;
  localparam int unsigned ADDR_WIDTH  = 12;
  localparam int unsigned MEM_DEPTH   = 256;
  localparam string       MEM_INIT    = "";

  // ---------------------------------------------------------------------------
  // Timescale and Clock
  // ---------------------------------------------------------------------------
  `timescale 1ns/1ps

  logic clk;
  logic resetn;

  // ---------------------------------------------------------------------------
  // AXI4-Lite Write Address Channel (AW)
  // ---------------------------------------------------------------------------
  logic                        s_axi_awvalid = 0;
  logic                        s_axi_awready;
  logic [ADDR_WIDTH-1:0]       s_axi_awaddr = 0;
  logic [2:0]                  s_axi_awprot = 0;

  // ---------------------------------------------------------------------------
  // AXI4-Lite Write Data Channel (W)
  // ---------------------------------------------------------------------------
  logic                        s_axi_wvalid = 0;
  logic                        s_axi_wready;
  logic [DATA_WIDTH-1:0]       s_axi_wdata = 0;
  logic [(DATA_WIDTH/8)-1:0]   s_axi_wstrb = 0;

  // ---------------------------------------------------------------------------
  // AXI4-Lite Write Response Channel (B)
  // ---------------------------------------------------------------------------
  logic                        s_axi_bvalid;
  logic                        s_axi_bready;
  logic [1:0]                  s_axi_bresp;

  // ---------------------------------------------------------------------------
  // AXI4-Lite Read Address Channel (AR)
  // ---------------------------------------------------------------------------
  logic                        s_axi_arvalid;
  logic                        s_axi_arready;
  logic [ADDR_WIDTH-1:0]       s_axi_araddr;
  logic [2:0]                  s_axi_arprot;

  // ---------------------------------------------------------------------------
  // AXI4-Lite Read Data Channel (R)
  // ---------------------------------------------------------------------------
  logic                        s_axi_rvalid;
  logic                        s_axi_rready;
  logic [DATA_WIDTH-1:0]       s_axi_rdata;
  logic [1:0]                  s_axi_rresp;

  // ---------------------------------------------------------------------------
  // DUT: AXI4-Lite Slave Top Module
  // ---------------------------------------------------------------------------
  s_axil_top #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .ADDR_WIDTH ( ADDR_WIDTH ),
    .MEM_DEPTH  ( MEM_DEPTH  ),
    .MEM_INIT   ( MEM_INIT   )
  ) dut (
    // Global signals
    .clk           ( clk           ),
    .resetn        ( resetn         ),

    // AXI4-Lite Write Address Channel (AW)
    .s_axi_awvalid ( s_axi_awvalid ),
    .s_axi_awready ( s_axi_awready ),
    .s_axi_awaddr  ( s_axi_awaddr  ),
    .s_axi_awprot  ( s_axi_awprot  ),

    // AXI4-Lite Write Data Channel (W)
    .s_axi_wvalid  ( s_axi_wvalid  ),
    .s_axi_wready  ( s_axi_wready  ),
    .s_axi_wdata   ( s_axi_wdata   ),
    .s_axi_wstrb   ( s_axi_wstrb   ),

    // AXI4-Lite Write Response Channel (B)
    .s_axi_bvalid  ( s_axi_bvalid  ),
    .s_axi_bready  ( s_axi_bready  ),
    .s_axi_bresp   ( s_axi_bresp   ),

    // AXI4-Lite Read Address Channel (AR)
    .s_axi_arvalid ( s_axi_arvalid ),
    .s_axi_arready ( s_axi_arready ),
    .s_axi_araddr  ( s_axi_araddr  ),
    .s_axi_arprot  ( s_axi_arprot  ),

    // AXI4-Lite Read Data Channel (R)
    .s_axi_rvalid  ( s_axi_rvalid  ),
    .s_axi_rready  ( s_axi_rready  ),
    .s_axi_rdata   ( s_axi_rdata   ),
    .s_axi_rresp   ( s_axi_rresp   )
  );

initial begin
    clk = 0;
    forever begin
        #5 clk = ~clk;
    end
end

initial begin
    resetn = 0;
    #10; resetn = 1;
    @(posedge clk);

    #10000;
    $finish;

end



initial
    $fsdbDumpvars();

endmodule