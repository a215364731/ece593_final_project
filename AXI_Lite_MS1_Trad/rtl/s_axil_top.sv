// =============================================================================
// s_axil_top.sv
// AXI4-Lite Slave IP - Top Level
//
// Description:
//   Parametrized AXI4-Lite slave with an internal block RAM.
//   Read and write paths are implemented in dedicated submodules:
//
//     s_axil_wr  -- AW, W, B channels
//     s_axil_rd   -- AR, R  channels
//
//   The two submodules share a simple dual-port memory array instantiated
//   at this level.  Write port has priority over the read port when both
//   target the same address in the same cycle (write-before-read).
//
// Parameters:
//   DATA_WIDTH  - AXI data bus width in bits. Must be 32 or 64.
//   ADDR_WIDTH  - AXI address bus width in bits (≤ 32).
//   MEM_DEPTH   - Number of DATA_WIDTH-wide words in the memory block.
//                 Must be a power-of-2 for clean address decode.
//   MEM_INIT    - Optional: Path to a $readmemh-compatible hex init file.
//                 Leave empty ("") to skip initialisation.
//
// Interface:
//   Standard AXI4-Lite slave (no ID, no LOCK, no CACHE, no QOS).
//
// Latency:
//   Writes: 0 wait-state (back-to-back transactions possible)
//   Reads:  1 clock cycle BRAM read latency
// =============================================================================

`timescale 1ns / 1ps

module s_axil_top #(
  parameter int unsigned DATA_WIDTH  = 32,           // 32 or 64
  parameter int unsigned ADDR_WIDTH  = 12,           // AXI byte address bits
  parameter int unsigned MEM_DEPTH   = 256,          // Words in the block RAM
  parameter string       MEM_INIT    = ""            // Optional hex init file
)(
  // ---------------------------------------------------------------------------
  // Global Signals
  // ---------------------------------------------------------------------------
  input  logic                       clk,
  input  logic                       resetn,

  // ---------------------------------------------------------------------------
  // AXI4-Lite Write Address Channel (AW)
  // ---------------------------------------------------------------------------
  input  logic                       s_axi_awvalid,
  output logic                       s_axi_awready,
  input  logic [ADDR_WIDTH-1:0]      s_axi_awaddr,
  input  logic [2:0]                 s_axi_awprot,

  // ---------------------------------------------------------------------------
  // AXI4-Lite Write Data Channel (W)
  // ---------------------------------------------------------------------------
  input  logic                       s_axi_wvalid,
  output logic                       s_axi_wready,
  input  logic [DATA_WIDTH-1:0]      s_axi_wdata,
  input  logic [(DATA_WIDTH/8)-1:0]  s_axi_wstrb,

  // ---------------------------------------------------------------------------
  // AXI4-Lite Write Response Channel (B)
  // ---------------------------------------------------------------------------
  output logic                       s_axi_bvalid,
  input  logic                       s_axi_bready,
  output logic [1:0]                 s_axi_bresp,

  // ---------------------------------------------------------------------------
  // AXI4-Lite Read Address Channel (AR)
  // ---------------------------------------------------------------------------
  input  logic                       s_axi_arvalid,
  output logic                       s_axi_arready,
  input  logic [ADDR_WIDTH-1:0]      s_axi_araddr,
  input  logic [2:0]                 s_axi_arprot,

  // ---------------------------------------------------------------------------
  // AXI4-Lite Read Data Channel (R)
  // ---------------------------------------------------------------------------
  output logic                       s_axi_rvalid,
  input  logic                       s_axi_rready,
  output logic [DATA_WIDTH-1:0]      s_axi_rdata,
  output logic [1:0]                 s_axi_rresp
);

  // ---------------------------------------------------------------------------
  // Local Parameters
  // ---------------------------------------------------------------------------
  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
  localparam int unsigned MEM_AW     = $clog2(MEM_DEPTH);

  // ---------------------------------------------------------------------------
  // Block RAM Array
  // ---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

  // Optional memory initialization
  initial begin
    if (MEM_INIT != "") begin
      $readmemh(MEM_INIT, mem);
    end
  end

  // ---------------------------------------------------------------------------
  // Write Port Wires (from s_axil_wr)
  // ---------------------------------------------------------------------------
  logic                  mem_w_en;
  logic [MEM_AW-1:0]    mem_waddr;
  logic [DATA_WIDTH-1:0] mem_wdata;
  logic [STRB_WIDTH-1:0] mem_wstrb;

  // ---------------------------------------------------------------------------
  // Read Port Wires (from/to s_axil_rd)
  // ---------------------------------------------------------------------------
  logic                  mem_r_en;
  logic [MEM_AW-1:0]    mem_raddr;
  logic [DATA_WIDTH-1:0] mem_rdata;

  // ---------------------------------------------------------------------------
  // Memory Read (registered — 1 cycle latency)
  //   Write-before-read: if write and read target the same address in the same
  //   cycle, the freshly-written value is forwarded to the read data output.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (mem_r_en) begin
      if (mem_w_en && (mem_waddr == mem_raddr)) begin
        // Forward write data to read output (write-before-read)
        mem_rdata <= apply_strobe(mem[mem_raddr], mem_wdata, mem_wstrb);
      end else begin
        mem_rdata <= mem[mem_raddr];
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Memory Write (byte-enable via WSTRB)
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (mem_w_en) begin
      for (int b = 0; b < STRB_WIDTH; b++) begin
        if (mem_wstrb[b]) begin
          mem[mem_waddr][b*8 +: 8] <= mem_wdata[b*8 +: 8];
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Helper Function: apply byte strobes to a word
  // ---------------------------------------------------------------------------
  function automatic logic [DATA_WIDTH-1:0] apply_strobe(
    input logic [DATA_WIDTH-1:0] base,
    input logic [DATA_WIDTH-1:0] wdata,
    input logic [STRB_WIDTH-1:0] wstrb
  );
    logic [DATA_WIDTH-1:0] result;
    result = base;
    for (int b = 0; b < STRB_WIDTH; b++) begin
      if (wstrb[b]) result[b*8 +: 8] = wdata[b*8 +: 8];
    end
    return result;
  endfunction

  // ---------------------------------------------------------------------------
  // Write Submodule
  // ---------------------------------------------------------------------------
  s_axil_wr #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .ADDR_WIDTH ( ADDR_WIDTH ),
    .MEM_DEPTH  ( MEM_DEPTH  )
  ) s_axil_wr_i (
    .clk           ( clk           ),
    .resetn         ( resetn         ),

    .s_axi_awvalid  ( s_axi_awvalid  ),
    .s_axi_awready  ( s_axi_awready  ),
    .s_axi_awaddr   ( s_axi_awaddr   ),
    .s_axi_awprot   ( s_axi_awprot   ),

    .s_axi_wvalid   ( s_axi_wvalid   ),
    .s_axi_wready   ( s_axi_wready   ),
    .s_axi_wdata    ( s_axi_wdata    ),
    .s_axi_wstrb    ( s_axi_wstrb    ),

    .s_axi_bvalid   ( s_axi_bvalid   ),
    .s_axi_bready   ( s_axi_bready   ),
    .s_axi_bresp    ( s_axi_bresp    ),

    .mem_w_en       ( mem_w_en       ),
    .mem_waddr      ( mem_waddr      ),
    .mem_wdata      ( mem_wdata      ),
    .mem_wstrb      ( mem_wstrb      )
  );

  // ---------------------------------------------------------------------------
  // Read Submodule
  // ---------------------------------------------------------------------------
  s_axil_rd #(
    .DATA_WIDTH ( DATA_WIDTH ),
    .ADDR_WIDTH ( ADDR_WIDTH ),
    .MEM_DEPTH  ( MEM_DEPTH  )
  ) s_axil_rd_i (
    .clk           ( clk           ),
    .resetn         ( resetn         ),

    .s_axi_arvalid  ( s_axi_arvalid  ),
    .s_axi_arready  ( s_axi_arready  ),
    .s_axi_araddr   ( s_axi_araddr   ),
    .s_axi_arprot   ( s_axi_arprot   ),

    .s_axi_rvalid   ( s_axi_rvalid   ),
    .s_axi_rready   ( s_axi_rready   ),
    .s_axi_rdata    ( s_axi_rdata    ),
    .s_axi_rresp    ( s_axi_rresp    ),

    .mem_r_en       ( mem_r_en       ),
    .mem_raddr      ( mem_raddr      ),
    .mem_rdata      ( mem_rdata      )
  );

endmodule
