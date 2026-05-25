// =============================================================================
// s_axil_wr.sv
// AXI4-Lite Slave IP - Write Channel Submodule
//
// Description:
//   Handles AXI4-Lite write transactions:
//     - Write Address Channel (AW)
//     - Write Data Channel    (W)
//     - Write Response Channel(B)
//
// Parameters:
//   DATA_WIDTH  - Width of the data bus in bits (32 or 64)
//   ADDR_WIDTH  - Width of the address bus in bits
//   MEM_DEPTH   - Number of addressable words in the memory block
// =============================================================================

`timescale 1ns / 1ps
`include "s_axil_defs.svh"

module s_axil_wr #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
)(
  // Clock and Reset
  input  logic                        clk,
  input  logic                        resetn,

  // AXI4-Lite Write Address Channel (AW)
  input  logic                        s_axi_awvalid,
  output logic                        s_axi_awready,
  input  logic [ADDR_WIDTH-1:0]       s_axi_awaddr,
  input  logic [2:0]                  s_axi_awprot,

  
  // AXI4-Lite Write Data Channel (W)
  input  logic                        s_axi_wvalid,
  output logic                        s_axi_wready,
  input  logic [DATA_WIDTH-1:0]       s_axi_wdata,
  input  logic [(DATA_WIDTH/8)-1:0]   s_axi_wstrb,

  
  // AXI4-Lite Write Response Channel (B)
  output logic                        s_axi_bvalid,
  input  logic                        s_axi_bready,
  output logic [1:0]                  s_axi_bresp,

  // Memory Interface
  output logic                         mem_w_en,
  output logic [$clog2(MEM_DEPTH)-1:0] mem_waddr,
  output logic [DATA_WIDTH-1:0]        mem_wdata,
  output logic [(DATA_WIDTH/8)-1:0]    mem_wstrb
);

  // Local Parameters
  localparam int unsigned STRB_WIDTH   = DATA_WIDTH / 8;
  localparam int unsigned WORD_BITS    = $clog2(STRB_WIDTH); // byte-offset bits
  localparam int unsigned MEM_AW       = $clog2(MEM_DEPTH);

  // Internal Registers
  // Latch AW channel
  logic                  aw_active;
  logic [ADDR_WIDTH-1:0] aw_addr_lat;
  logic [2:0]            aw_prot_lat;

  // Latch W channel
  logic                  w_active;
  logic [DATA_WIDTH-1:0] w_data_lat;
  logic [STRB_WIDTH-1:0] w_strb_lat;

  // Response
  logic                  b_pending;
  logic [1:0]            b_resp_lat;

  // AW Channel Handshake
  // Accept address when not already holding one
  assign s_axi_awready = resetn & ~aw_active;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      aw_active   <= 1'b0;
      aw_addr_lat <= '0;
      aw_prot_lat <= '0;
    end else begin
      if (s_axi_awvalid && s_axi_awready) begin
        aw_active   <= 1'b1;
        aw_addr_lat <= s_axi_awaddr;
        aw_prot_lat <= s_axi_awprot;
      end else if (aw_active && w_active) begin
        // Both channels received; clear after write
        aw_active <= 1'b0;
      end
    end
  end

  // W Channel Handshake
  assign s_axi_wready = resetn & ~w_active;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      w_active   <= 1'b0;
      w_data_lat <= '0;
      w_strb_lat <= '0;
    end else begin
      if (s_axi_wvalid && s_axi_wready) begin
        w_active   <= 1'b1;
        w_data_lat <= s_axi_wdata;
        w_strb_lat <= s_axi_wstrb;
      end else if (aw_active && w_active) begin
        w_active <= 1'b0;
      end
    end
  end

  // Write to Memory
  // Both channels must be latched; fire write and initiate B response
  logic write_fire;
  assign write_fire = aw_active && w_active && !b_pending;

  // Address decode: strip byte offset, check range
  logic addr_in_range;
  logic [MEM_AW-1:0] word_addr;

  assign word_addr     = aw_addr_lat[MEM_AW + WORD_BITS - 1 : WORD_BITS];
  assign addr_in_range = (aw_addr_lat[ADDR_WIDTH-1:WORD_BITS] < MEM_DEPTH);

  assign mem_w_en   = write_fire & addr_in_range;
  assign mem_waddr = word_addr;
  assign mem_wdata = w_data_lat;
  assign mem_wstrb = w_strb_lat;

  // B Channel (Write Response)
  always_ff @(posedge clk) begin
    if (!resetn) begin
      b_pending  <= 1'b0;
      b_resp_lat <= RESP_OKAY;
    end else begin
      if (write_fire) begin
        b_pending  <= 1'b1;
        b_resp_lat <= addr_in_range ? RESP_OKAY : RESP_SLVERR;
      end else if (b_pending && s_axi_bready) begin
        b_pending <= 1'b0;
      end
    end
  end

  assign s_axi_bvalid = b_pending;
  assign s_axi_bresp  = b_resp_lat;

endmodule
