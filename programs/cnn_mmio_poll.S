# CNN MMIO polling demo with UART image loading, batch inference, LED,
# and UART result output.
#
# The host sends one 1024-byte image at a time. For each image this program
# receives the bytes through UART RX, stores them at data RAM base 0xC00,
# starts the CNN accelerator, sends the predicted digit plus CR/LF, then loops
# back to wait for the next image.
#
# Only lw/sw are used for peripheral accesses; sb is used for data RAM image
# writes.
#
# CNN CONTROL: 0x80001000
# CNN STATUS : 0x80001004, bit1 = done
# CNN BASE   : 0x80001008
# CNN RESULT : 0x8000100c
# LED        : 0x80002000
# UART TXDATA: 0x80003000
# UART STATUS: 0x80003004, bit0 = tx_busy or tx pending, bit1 = rx_valid
# UART RXDATA: 0x80003008, read clears rx_valid

    lui   x16, 0x80003          # x16 = UART MMIO base, 0x80003000
    lui   x10, 0x80001          # x10 = CNN MMIO base, 0x80001000
    lui   x15, 0x80002          # x15 = LED MMIO base, 0x80002000
    lui   x19, 0x00001          # x19 = 0x00001000
    addi  x19, x19, -1024       # x19 = CNN image base, 0x00000c00
    sw    x19, 8(x10)           # write CNN image base once

receive_image:
    addi  x20, x19, 0           # x20 = current destination pointer
    addi  x21, x0, 1024         # x21 = bytes remaining

_uart_wait_image_byte:
    lw    x11, 4(x16)           # read UART STATUS
    andi  x11, x11, 2           # isolate rx_valid
    beq   x11, x0, _uart_wait_image_byte

    lw    x12, 8(x16)           # read RXDATA; clears rx_valid
    sb    x12, 0(x20)           # store received image byte
    addi  x20, x20, 1           # advance destination pointer
    addi  x21, x21, -1          # count one received byte
    bne   x21, x0, _uart_wait_image_byte

    addi  x12, x0, 1
    sw    x12, 0(x10)           # CONTROL.start = 1

_wait_done_clear:
    lw    x13, 4(x10)           # old done may still be high after last run
    andi  x13, x13, 2
    bne   x13, x0, _wait_done_clear

poll:
    lw    x13, 4(x10)           # read STATUS
    andi  x13, x13, 2           # isolate STATUS.done
    beq   x13, x0, poll

    lw    x14, 12(x10)          # read RESULT
    sw    x14, 0(x15)           # write result to LED MMIO

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

    beq   x0, x0, receive_image # wait for the next host image
