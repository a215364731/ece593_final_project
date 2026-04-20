`timescale 1ns / 1ps

module testbench;

  localparam int unsigned DATA_WIDTH  = 32;
  localparam int unsigned ADDR_WIDTH  = 12;
  localparam int unsigned MEM_DEPTH   = 256;
  localparam string       MEM_INIT    = "";

  logic clk;
  logic resetn;

  // Write address channel
  logic                        s_axi_awvalid = 0;
  logic                        s_axi_awready;
  logic [ADDR_WIDTH-1:0]       s_axi_awaddr = 0;
  logic [2:0]                  s_axi_awprot = 0;

  // Write data channel
  logic                        s_axi_wvalid = 0;
  logic                        s_axi_wready;
  logic [DATA_WIDTH-1:0]       s_axi_wdata = 0;
  logic [(DATA_WIDTH/8)-1:0]   s_axi_wstrb = 0;

  // Write response channel
  logic                        s_axi_bvalid;
  logic                        s_axi_bready;
  logic [1:0]                  s_axi_bresp;

  // Read address channel
  logic                        s_axi_arvalid;
  logic                        s_axi_arready;
  logic [ADDR_WIDTH-1:0]       s_axi_araddr;
  logic [2:0]                  s_axi_arprot;

  // Read data channel
  logic                        s_axi_rvalid;
  logic                        s_axi_rready;
  logic [DATA_WIDTH-1:0]       s_axi_rdata;
  logic [1:0]                  s_axi_rresp;

  s_axil_top #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .ADDR_WIDTH ( ADDR_WIDTH ),
    .MEM_DEPTH  ( MEM_DEPTH  ),
    .MEM_INIT   ( MEM_INIT   )
  ) dut (
    .clk           ( clk           ),
    .resetn        ( resetn         ),

    .s_axi_awvalid ( s_axi_awvalid ),
    .s_axi_awready ( s_axi_awready ),
    .s_axi_awaddr  ( s_axi_awaddr  ),
    .s_axi_awprot  ( s_axi_awprot  ),

    .s_axi_wvalid  ( s_axi_wvalid  ),
    .s_axi_wready  ( s_axi_wready  ),
    .s_axi_wdata   ( s_axi_wdata   ),
    .s_axi_wstrb   ( s_axi_wstrb   ),

    .s_axi_bvalid  ( s_axi_bvalid  ),
    .s_axi_bready  ( s_axi_bready  ),
    .s_axi_bresp   ( s_axi_bresp   ),

    .s_axi_arvalid ( s_axi_arvalid ),
    .s_axi_arready ( s_axi_arready ),
    .s_axi_araddr  ( s_axi_araddr  ),
    .s_axi_arprot  ( s_axi_arprot  ),

    .s_axi_rvalid  ( s_axi_rvalid  ),
    .s_axi_rready  ( s_axi_rready  ),
    .s_axi_rdata   ( s_axi_rdata   ),
    .s_axi_rresp   ( s_axi_rresp   )
  );

  task write_transaction(logic [ADDR_WIDTH-1:0] addr, logic [DATA_WIDTH-1:0] data);
    s_axi_awaddr  <= addr;
    s_axi_awvalid <= 1;
    s_axi_wdata   <= data;
    s_axi_wstrb   <= '1;  // All bytes valid
    s_axi_wvalid  <= 1;
    s_axi_bready  <= 1;

    // Wait for write address ready
    @(posedge clk);
    while (~s_axi_awready || ~s_axi_wready) begin
      @(posedge clk);
    end

    // Deassert write signals
    s_axi_awvalid <= 0;
    s_axi_wvalid  <= 0;

    // Wait for write response
    @(posedge clk);
    while (~s_axi_bvalid) begin
      @(posedge clk);
    end

    // Check write response (OKAY = 2'b00)
    if (s_axi_bresp != 2'b00) begin
      $display("[ERROR] Write response error: bresp = %b at time %t", s_axi_bresp, $time);
    end else begin
      $display("[INFO] Write transaction successful at address 0x%h with data 0x%h at time %t", addr, data, $time);
    end

    s_axi_bready  <= 0;
  endtask

  task read_transaction(logic [ADDR_WIDTH-1:0] addr, output logic [DATA_WIDTH-1:0] data);
    s_axi_araddr  <= addr;
    s_axi_arvalid <= 1;
    s_axi_rready  <= 1;

    // Wait for read address ready
    @(posedge clk);
    while (~s_axi_arready) begin
      @(posedge clk);
    end

    // Deassert read address valid
    s_axi_arvalid <= 0;

    // Wait for read data valid
    @(posedge clk);
    while (~s_axi_rvalid) begin
      @(posedge clk);
    end

    // Capture read data and check response
    data = s_axi_rdata;
    if (s_axi_rresp != 2'b00) begin
      $display("[ERROR] Read response error: rresp = %b at time %t", s_axi_rresp, $time);
    end else begin
      $display("[INFO] Read transaction successful at address 0x%h with data 0x%h at time %t", addr, data, $time);
    end

    s_axi_rready  <= 0;
  endtask


initial begin
    clk = 0;
    forever begin
        #5 clk = ~clk;
    end
end

logic [ADDR_WIDTH-1:0] addr;
logic [DATA_WIDTH-1:0] data;
localparam RANDOM_SEED = 1;

initial begin
    $srandom(RANDOM_SEED);
    resetn = 0;
    #10; resetn = 1;
    repeat(10)@(posedge clk);
    for(int i = 0; i < 256; i++) begin
      addr = i*4;
      for(int j = 0; j < 1024; j++) begin
        data = $urandom();
        write_transaction(addr, data);
        read_transaction(addr, data);
      end
    end


    #100;
    $finish;

end



initial
    $fsdbDumpvars();

endmodule