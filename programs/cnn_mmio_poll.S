# CNN MMIO polling demo with LED and UART result output.
# Only lw/sw are used for peripheral accesses.
#
# CNN CONTROL: 0x80001000
# CNN STATUS : 0x80001004, bit1 = done
# CNN BASE   : 0x80001008
# CNN RESULT : 0x8000100c
# LED        : 0x80002000
# UART TXDATA: 0x80003000
# UART STATUS: 0x80003004, bit0 = tx_busy or tx pending

    lui   x10, 0x80001          # x10 = 0x80001000
    lui   x11, 0x00001          # x11 = 0x00001000
    addi  x11, x11, -1024       # x11 = 0x00000c00
    sw    x11, 8(x10)           # write CNN image base

    addi  x12, x0, 1
    sw    x12, 0(x10)           # CONTROL.start = 1

poll:
    lw    x13, 4(x10)           # read STATUS
    andi  x13, x13, 2           # isolate STATUS.done
    beq   x13, x0, poll

    lw    x14, 12(x10)          # read RESULT
    lui   x15, 0x80002          # x15 = 0x80002000
    sw    x14, 0(x15)           # write result to LED MMIO

    lui   x16, 0x80003          # x16 = 0x80003000
    addi  x17, x14, 48          # convert digit 0..9 to ASCII

_uart_wait_digit:
    lw    x18, 4(x16)           # read UART STATUS
    andi  x18, x18, 1           # isolate tx_busy_or_pending
    bne   x18, x0, _uart_wait_digit
    sw    x17, 0(x16)           # send predicted digit

_uart_wait_cr:
    lw    x18, 4(x16)
    andi  x18, x18, 1
    bne   x18, x0, _uart_wait_cr
    addi  x17, x0, 13           # carriage return
    sw    x17, 0(x16)

_uart_wait_lf:
    lw    x18, 4(x16)
    andi  x18, x18, 1
    bne   x18, x0, _uart_wait_lf
    addi  x17, x0, 10           # line feed
    sw    x17, 0(x16)

    ecall
