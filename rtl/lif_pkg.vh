`ifndef LIF_PKG_VH
`define LIF_PKG_VH
// Fixed-point Q4.12 (signed 16-bit): 1 sign, 3 integer, 12 fractional
`ifndef Q
`define Q     12
`endif

`ifndef W
`define W     16
`endif

`define FX(x) $rtoi((x) * (1 << `Q))
`define FX_MAX ((1 << (`W-1)) - 1)
`define FX_MIN (-(1 << (`W-1)))
`endif
