# Versions of the Project

In future development, I will publish several versions of the project from a simple structure to a complicated SoC, and each version will be recorded here.

## v1

This is the first successful implementation of this project, with a CPU and a CNN module combined. Finished in 2026-07-26.

### Workflow

The v1 workflow is intentionally simple:

1. Train the PyTorch CNN on MNIST resized to `32x32`.
2. Quantize the trained weights and biases into integer `.mem` files.
3. Generate `cnn.mem` from a selected MNIST test image.
4. Let the CPU execute its small built-in RISC-V program.
5. Decode the custom CNN instruction, raise `cnn_en`, and start the accelerator.
6. Run the CNN core with fixed-point arithmetic and block-memory-backed parameters.
7. Show the final predicted digit on four active-low LEDs.

The instruction memory is loaded from `mem_files/instruction.mem`. In the original v1 snapshot, this image contained a small GCD program followed by a custom CNN trigger instruction (`FE00707F`) and then `ecall`; in the current tree, `instruction.mem` is rebuilt for later MMIO and UART-driven programs.

### Hardware Design

The hardware is built around a five-stage RISC-V CPU pipeline and a sequential CNN accelerator.

CPU-side modules include:

- `PC_Module`, `Instruction_Memory`, `Branch_Jump`, and `Branch_Table` for instruction fetch and branch control.
- `Register_File`, `Control_Unit`, `ALU`, `Data_Memory`, and `Writeback_Unit` for the main datapath.
- `IF_ID_reg`, `ID_EX_reg`, `EX_MEM_Reg`, and `MEM_WB_Reg` for pipeline staging.
- `Forwarding_Unit` and `Hazard_Detection_Unit` for basic pipeline hazard handling.

Accelerator-side logic is implemented in `cnn_core`. The current CNN topology is:

```text
Input: 32x32 grayscale image
Conv1: 1 channel, 3x3 valid convolution -> ReLU -> 30x30
Pool1: 2x2 max pooling -> 15x15
Conv2: 1 channel, 3x3 valid convolution -> ReLU -> 13x13
Pool2: 2x2 max pooling -> 6x6
FC:    36 inputs -> 10 output classes
Argmax: predicted digit 0-9
```

The accelerator uses one shared multiply-accumulate path controlled by an FSM. This reduces resource usage compared with a fully parallel CNN datapath, which is important for a first FPGA implementation. The design stores the input image, kernels, biases, fully connected weights, and intermediate feature maps in Verilog memories with block-RAM style attributes where appropriate.

The top-level clock input is divided internally into a 50 MHz CPU clock and a 20 MHz CNN clock. The result is sent to `Four_LED_Binary_Display`, where `ledr = ~predicted_class_LED`; therefore a lit LED represents a `1` bit in the predicted class, but the physical output pins are active-low.

### Software Infrastructure and Verification

The software infrastructure is used to keep the hardware implementation tied to a reproducible neural-network model:

- `models/cnn_model.py` defines the exact CNN architecture used by training and verification.
- `scripts/train.py` trains the model for MNIST classification and stores the checkpoint in `weights/mnist_cnn.pth`.
- `scripts/quantize.py` exports the fixed-point format used by the Verilog CNN datapath: signed int16 weights, signed int32 biases, and `SHIFT1 = SHIFT2 = SHIFT_FC = 14`.
- `scripts/quantize_adaptive.py` can also produce `mem_files/fixed/` and `mem_files/adapt/` variants for comparing fixed and per-layer shifts.
- `scripts/testmem.py` converts one MNIST test image into `mem_files/cnn.mem` and saves `mem_files/test_image.png` for visual checking.
- `scripts/sim.py` is a hardware-style integer CNN simulator. It reads the same `.mem` files as Verilog and mirrors the fixed-point datapath.
- `scripts/batch_accuracy.py` compares floating-point PyTorch inference, quantized/dequantized weights, and hardware-style integer inference across a batch of MNIST samples.
- `scripts/debug_verify.py` provides deeper checks for bias scaling, fully connected weight layout, and bit-width behavior.

The fixed-point convention used by the v1 design is:

```text
image_int  = round(image_float * 255)
weight_int = round(weight_float * 2^SHIFT)
bias_int   = round(bias_float * 255 * 2^SHIFT)
output_int = relu((sum(image_int * weight_int) + bias_int) >>> SHIFT)
```

This keeps activations approximately at image scale after each layer while allowing the Verilog implementation to use shift-based requantization instead of division.

## v2

This version changes the CPU-CNN control path from a custom instruction to a simple memory-mapped I/O interface. The CPU controls the accelerator, LED output, and UART through ordinary `lw` and `sw` instructions, and the integrated design has been verified on the FPGA board. Finished in 2026-08-04.

### Workflow

The v2 workflow is controlled by a hand-written RISC-V polling program:

1. Train the PyTorch CNN on MNIST resized to `32x32`.
2. Quantize the trained weights and biases into integer `.mem` files.
3. Generate `cnn.mem` and `cnn_b*.mem` from a selected MNIST test image.
4. Build `programs/cnn_mmio_poll.S` into `mem_files/instruction.mem` with `scripts/asm_to_mem.py` or `make program`.
5. After reset, the CPU writes the CNN input base address `0xC00` to the CNN base register.
6. The CPU writes the start bit in the CNN control register.
7. The CPU polls the CNN status register until the `done` bit is set.
8. The CPU reads the prediction result, writes it to the LED register, and sends the ASCII digit plus CR/LF over UART.

### Hardware Design

The v2 top level is `RVCCC`. It keeps the five-stage RV32I CPU and sequential CNN accelerator from v1, while adding the `Mapped_IO` peripheral block, a board LED register, and an 8N1 UART running at 115200 baud by default.

The current memory map is:

```text
0x80001000  CNN CONTROL: bit0=start, bit1=clear error, bit2=soft reset
0x80001004  CNN STATUS : bit0=busy, bit1=done, bit2=error
0x80001008  CNN BASE   : input image byte base address
0x8000100C  CNN RESULT : predicted class in bits [3:0]
0x80002000  LED        : four-bit LED output value
0x80003000  UART TXDATA: write one byte to transmit
0x80003004  UART STATUS: bit0=tx_busy_or_pending, bit1=rx_valid
0x80003008  UART RXDATA: most recently received byte
```

Only naturally aligned word accesses are supported for the mapped peripherals. Unsupported offsets read as zero or act as harmless no-ops. The CNN image is 1024 bytes inside the 4KB data memory, so the base address must be four-byte aligned and no greater than `0xC00`. The base register resets to `0xC00`, but the polling program writes it explicitly before starting inference.

The CNN start register generates a one-cycle start pulse when the accelerator is idle. A start request while the CNN is busy sets the error bit. Writing bit1 of `CNN CONTROL` clears the error bit, and writing bit2 asserts a CNN soft reset and clears the error bit. The CNN reports completion directly through its FSM-driven `busy` and `done` outputs.

The data RAM is implemented as four byte-lane true dual-port memories. The CPU side supports RV32I byte, halfword, and word loads/stores through `funct3`; the CNN side uses byte addressing to read the input image from the selected base address. The checked-in lane files initialize the CPU data region in the first 3KB and, in v2, the CNN image region in the final 1KB.

`CLK_Gen` derives both `clk_cpu` and `clk_cnn` from the same divided 25 MHz clock. This keeps v2 free of clock-domain crossing issues while the MMIO control path is being validated. Separate CPU and accelerator clocks are reserved for a later version.

### Software Infrastructure and Verification

- `programs/cnn_mmio_poll.S` contains the hand-written polling program for CNN start/status/result, LED output, and UART transmission.
- `scripts/asm_to_mem.py` assembles RV32I code into the 256-word `mem_files/instruction.mem` image used by `Instruction_Memory`.
- `make program ASM=programs/cnn_mmio_poll.S` is the Makefile wrapper for rebuilding the instruction memory.
- The program uses only ordinary `lw` and `sw` instructions for peripheral access and polls UART `tx_busy_or_pending` before each transmitted byte.
- `testbench/RVCCC_tb.v` verifies the complete MMIO flow and prints both the final LED prediction and UART bytes.
- `testbench/RVCCC_rv32i_tb.v` continues to verify the base RV32I datapath with an injected self-test program.

## v3

This is the current implementation. It keeps the v2 MMIO control model, but changes the input-image path from a preloaded CNN memory image to runtime UART loading. The CPU now waits for the host computer to send a 1024-byte MNIST image, stores it into shared data RAM, starts the CNN accelerator, returns the predicted digit through UART, and loops back for the next image. The latest v3.3 development has been batch-tested on the FPGA board and can report result accuracy from the host script. Finished in 2026-08-06.

### Workflow

The v3 workflow turns the board into a simple UART-controlled inference device:

1. Train the PyTorch CNN on MNIST resized to `32x32`.
2. Quantize the trained weights and biases into integer `.mem` files.
3. Build `programs/cnn_mmio_poll.S` into `mem_files/instruction.mem` with `scripts/asm_to_mem.py` or `make program`.
4. Start the FPGA design and let the CPU write the CNN image base address `0xC00` to the CNN base register.
5. On the host computer, use `scripts/uart_test.py` to generate or load one 1024-byte image.
6. Send the image bytes through UART RX to the board.
7. The CPU polls `UART STATUS.rx_valid`, reads `UART RXDATA`, and stores each byte into data RAM with `sb` starting at address `0xC00`.
8. After receiving 1024 bytes, the CPU writes the CNN start bit in `CNN CONTROL`.
9. The CPU waits for any stale `done` state to clear, then polls `CNN STATUS.done` until the new inference finishes.
10. The CPU reads `CNN RESULT`, writes it to the LED register, and sends the ASCII digit plus CR/LF through UART TX.
11. The CPU loops back to receive the next image, so the host can run selected-image tests or batch accuracy tests without rebuilding the FPGA memory image.

### Hardware Design

The v3 hardware keeps the same top-level `RVCCC` integration: five-stage RV32I CPU, shared data memory, `Mapped_IO`, `cnn_core`, active-low LED output, and UART. The important change is that UART RX has become part of the actual data path rather than only a peripheral test feature.

`Mapped_IO` exposes the UART registers used by the CPU program:

```text
0x80003000  UART TXDATA: write bits [7:0] to transmit one byte
0x80003004  UART STATUS: bit0=tx_busy_or_pending, bit1=rx_valid
0x80003008  UART RXDATA: read bits [7:0]; read clears rx_valid
```

The RX byte is latched inside `Mapped_IO` as `uart_rx_data_reg`, with `uart_rx_valid_reg` set when `uart_top` reports a received byte. Reading `UART RXDATA` clears the valid flag, which gives the polling software a simple handshake. UART TX remains guarded by `tx_busy_or_pending`, and software waits before writing each outgoing byte.

`Data_Memory` remains a 4KB four-lane true dual-port RAM. The CPU port supports byte stores, so the UART receive loop can write the incoming image one byte at a time. The CNN port reads the same memory region by byte address after the CPU has finished loading the image. Since the UART image is now written at runtime, `scripts/testmem.py` intentionally no longer regenerates `cnn_b*.mem`; `cnn.mem` is used by software tools and the host sender, while the board receives the image through UART.

The clocking strategy is still conservative: `CLK_Gen` derives both `clk_cpu` and `clk_cnn` from the same 25 MHz divided clock. This avoids CDC complexity while the UART-to-RAM-to-CNN flow is being verified.

### Software Infrastructure and Verification

- `programs/cnn_mmio_poll.S` is now a persistent receive-infer-transmit loop. It receives 1024 UART bytes, stores them at `0xC00`, starts CNN inference, outputs LED and UART results, then waits for the next image.
- `programs/uart_echo.S` provides a minimal UART RX/TX loopback program that was used to verify the receive path before the full image-loading flow.
- `scripts/uart_test.py` is the host-side board test tool. It can list serial ports, auto-select a likely port, send an existing `cnn.mem`, generate selected MNIST indices with `--image-index`, or run a batch test with `--batch COUNT`.
- In generated-image and batch modes, `scripts/uart_test.py` calls `scripts/testmem.py`, sends the resulting 1024 bytes, waits for one result line, parses the ASCII digit, compares it with the MNIST label, and prints correctness or aggregate accuracy.
- `scripts/testmem.py` still writes `mem_files/cnn.mem` and `mem_files/test_image.png`, but its old `cnn_b*.mem` generation is disabled because the board image region is no longer initialized from lane files.
- The v3.1 development first attempted to upload `cnn.mem` through UART and was not yet successful. v3.2 reached board-level batch send/receive behavior, with an intermittent reset/start issue noted at that time. v3.3 resolved the practical batch inference flow and added host-side accuracy reporting after successful board testing.
