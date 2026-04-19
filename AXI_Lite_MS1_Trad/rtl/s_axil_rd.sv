// =============================================================================
// s_axil_rd.sv
// AXI4-Lite Slave IP - Read Channel Submodule
//
// Description:
//   Handles AXI4-Lite read transactions:
//     - Read Address Channel (AR)
//     - Read Data Channel    (R)
//
// Parameters:
//   DATA_WIDTH  - Width of the data bus in bits (32 or 64)
//   ADDR_WIDTH  - Width of the address bus in bits
//   MEM_DEPTH   - Number of addressable words in the memory block
// =============================================================================

`timescale 1ns / 1ps
`include "s_axil_defs.svh"

module s_axil_rd #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 12,
  parameter int unsigned MEM_DEPTH  = 256
)(
  // Clock and Reset
  input  logic                        clk,
  input  logic                        resetn,


  // AXI4 Lite Read Address Channel (AR)
  input  logic                        s_axi_arvalid,
  output logic                        s_axi_arready,
  input  logic [ADDR_WIDTH-1:0]       s_axi_araddr,
  input  logic [2:0]                  s_axi_arprot,


  // AXI4 Lite Read Data Channel (R)
  output logic                        s_axi_rvalid,
  input  logic                        s_axi_rready,
  output logic [DATA_WIDTH-1:0]       s_axi_rdata,
  output logic [1:0]                  s_axi_rresp,


  // Memory Interface
  output logic                         mem_r_en,
  output logic [$clog2(MEM_DEPTH)-1:0] mem_raddr,
  input  logic [DATA_WIDTH-1:0]        mem_rdata
);

  // Local Parameters
  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
  localparam int unsigned WORD_BITS  = $clog2(STRB_WIDTH);
  localparam int unsigned MEM_AW     = $clog2(MEM_DEPTH);

  // Internal Registers
  logic                  ar_active;    // AR handshake has been accepted
  logic [ADDR_WIDTH-1:0] ar_addr_lat;  // Latched read address
  logic                  ar_in_range;  // Address in-range flag

  logic                  r_valid;      // R channel valid
  logic [DATA_WIDTH-1:0] r_data;       // R channel data
  logic [1:0]            r_resp;       // R channel response

  // One-cycle pipeline flag: memory read issued, data available next cycle
  logic                  read_pending;
  logic                  read_in_range_d;

  // AR Channel Handshake
  // Accept new address only when no read is in flight
  assign s_axi_arready = resetn & ~ar_active & ~read_pending & ~r_valid;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      ar_active    <= 1'b0;
      ar_addr_lat  <= '0;
      ar_in_range  <= 1'b0;
    end else begin
      if (s_axi_arvalid && s_axi_arready) begin
        ar_active   <= 1'b1;
        ar_addr_lat <= s_axi_araddr;
        ar_in_range <= (s_axi_araddr[ADDR_WIDTH-1:WORD_BITS] < MEM_DEPTH);
      end else if (ar_active) begin
        // Consumed on the same cycle we issue the read
        ar_active <= 1'b0;
      end
    end
  end

  // Issue Memory Read (registered 1-cycle latency)
  assign mem_r_en   = ar_active & ar_in_range;
  assign mem_raddr = ar_addr_lat[MEM_AW + WORD_BITS - 1 : WORD_BITS];

  // Pipeline: track that data will be available next cycle
  always_ff @(posedge clk) begin
    if (!resetn) begin
      read_pending    <= 1'b0;
      read_in_range_d <= 1'b0;
    end else begin
      read_pending    <= ar_active;         // Goes high cycle after AR accepted
      read_in_range_d <= ar_in_range;
    end
  end

  // R Channel
  always_ff @(posedge clk) begin
    if (!resetn) begin
      r_valid <= 1'b0;
      r_data  <= '0;
      r_resp  <= RESP_OKAY;
    end else begin
      if (read_pending) begin
        r_valid <= 1'b1;
        r_data  <= read_in_range_d ? mem_rdata : '0;
        r_resp  <= read_in_range_d ? RESP_OKAY : RESP_SLVERR;
      end else if (r_valid && s_axi_rready) begin
        r_valid <= 1'b0;
      end
    end
  end

  assign s_axi_rvalid = r_valid;
  assign s_axi_rdata  = r_data;
  assign s_axi_rresp  = r_resp;

endmodule
