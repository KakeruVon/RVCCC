# UART polling loopback test.
# Wait for one received byte, then transmit the same byte.
#
# UART TXDATA: 0x80003000
# UART STATUS: 0x80003004
#   bit0 = tx_busy_or_pending
#   bit1 = rx_valid
# UART RXDATA: 0x80003008
#
# This program does not access the CNN or LED MMIO registers.

    lui   x10, 0x80003          # x10 = UART MMIO base, 0x80003000

_uart_wait_rx:
    lw    x11, 4(x10)           # read UART STATUS
    andi  x11, x11, 2           # isolate rx_valid
    beq   x11, x0, _uart_wait_rx

    lw    x12, 8(x10)           # read RXDATA; clears rx_valid

_uart_wait_tx:
    lw    x11, 4(x10)           # read UART STATUS
    andi  x11, x11, 1           # isolate tx_busy_or_pending
    bne   x11, x0, _uart_wait_tx

    sw    x12, 0(x10)           # transmit the received byte
    jal   x0, _uart_wait_rx     # echo bytes forever
