// ================================================================
// UART Top Module
// Properties of this UART module:
// - 8 data bits
// - 1 stop bit
// - No parity
// - Baud rate and clock frequency configurable via parameter
// ================================================================
`timescale 1ns/1ps
module uart_top #(
    parameter clk_freq = 25_000_000,
    parameter baud = 115200
) (
    input wire clk,
    input wire rst,
    input wire tx_valid,
    input wire [7:0] tx_data,
    output wire tx_busy,
    output wire tx,
    input wire rx,
    output wire rx_valid,
    output wire [7:0] rx_data
);

uart_tx #(
    .clk_freq(clk_freq),
    .baud(baud)
) uart_tx_inst (
    .clk(clk),
    .rst(rst),
    .tx_valid(tx_valid),
    .tx_data(tx_data),
    .tx_busy(tx_busy),
    .tx(tx)
);
uart_rx #(
    .clk_freq(clk_freq),
    .baud(baud)
) uart_rx_inst (
    .clk(clk),
    .rst(rst),
    .rx(rx),
    .rx_valid(rx_valid),
    .rx_data(rx_data)
);

endmodule