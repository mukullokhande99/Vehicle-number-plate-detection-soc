# Functional chip I/O budget

`plate_ocr_soc_top` has **32 functional signal pads**.  Its power, ground,
ESD, PLL/analog, and foundry pad-frame connections are deliberately outside RTL
and must be budgeted by the physical-integration owner.

| Function | Signals | Pads |
|---|---|---:|
| Clock and reset | `sys_clk`, `rst_n` | 2 |
| QSPI camera data | `cam_qspi_sclk`, `cam_qspi_cs_n`, `cam_qspi_dq[3:0]` | 6 |
| Camera control | `cam_i2c_scl`, `cam_i2c_sda` | 2 |
| Boot/model flash | `flash_qspi_sclk`, `flash_qspi_cs_n`, `flash_qspi_dq[3:0]` | 6 |
| Console | `uart_tx`, `uart_rx` | 2 |
| General I/O | `gpio[7:0]` | 8 |
| External interrupt | `ext_irq` | 1 |
| JTAG test access | `jtag_tck`, `jtag_tms`, `jtag_tdi`, `jtag_tdo`, `jtag_trst_n` | 5 |
| **Total** |  | **32** |

The QSPI camera interface assumes a module that streams raw RGB565 after
configuration.  USB webcams cannot connect to this interface directly.
