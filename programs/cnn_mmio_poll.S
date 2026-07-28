# CNN MMIO polling demo.
# Only lw/sw are used for peripheral accesses.
#
# CNN CONTROL: 0x80001000
# CNN STATUS : 0x80001004, bit1 = done
# CNN BASE   : 0x80001008
# CNN RESULT : 0x8000100c
# LED        : 0x80002000

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
    lui   x15, 0x80002           # x15 = 0x80002000
    sw    x14, 0(x15)           # write result to LED MMIO
    ecall
