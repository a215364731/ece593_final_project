`ifndef S_AXIL_DEFS
`define S_AXIL_DEFS

typedef enum logic [1:0] {
  RESP_OKAY   = 2'b00,  // Normal access success
  RESP_EXOKAY = 2'b01,  // Exclusive access success
  RESP_SLVERR = 2'b10,  // Slave error
  RESP_DECERR = 2'b11   // Decode error
} axi_resp_t;

`endif