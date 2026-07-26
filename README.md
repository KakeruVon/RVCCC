# RVCCC - RISC-V Core Controlled CNN accelerator
An SoC Project on FPGA featuring a RISC-V CPU core with a CNN accelerating module. Successfully implemented on Zynq-7020. Got the original project structure from [`RISC-V-Core-with-Integrated-CNN-Accelerator`](https://github.com/dev-the-desai/RISC-V-Core-with-Integrated-CNN-Accelerator) by `dev-the-desai`, and it has been enriched in multiple ways.

This project is now developing under a progressive pattern. Currently, I finished the first version, which is barely a CPU and an accelerating module put together. In further development, the CPU will be a control center of the whole process, arranging CNN module, bus, as well as communication with the host computer.

The purpose of this project is to accelerate neural network inferencing with hardware logic. I built a CNN with 2 convolution layers and 1 fully connected layer, trained with MNIST dataset, and implemented the model on FPGA to recognize the numbers in MNIST test images.

In early development, I implemented the Verilog code with [`nvboard`](https://github.com/NJU-ProjectN/nvboard), then I moved to an actual Xilinx [Zynq-7020]([ALINX AMD Xilinx Zynq 7000 SoC XC7Z020 zynq7020 FPGA Development Board / Evaluation Kit - AX7020](https://www.en.alinx.com/Product/SoC-development-Boards/Zynq-7000-SoC/AX7020.html)) board.



## File Structure

The project files include the infrastructure, the hardware logic, and the software stack. 

```text
RVCCC/
|-- vsrc/
|   `-- cpu.v                  # Top-level Verilog source: RISC-V CPU, CNN core, LED output logic
|-- testbench/
|   `-- cpu_tb.v               # Simulation testbench for the integrated CPU + CNN design
|-- csrc/
|   `-- run.cpp                # Verilator + NVBoard simulation entry
|-- constr/
|   |-- cpu.xdc                # Vivado FPGA pin and clock constraints
|   `-- cpu.nxdc               # NVBoard pin mapping
|-- models/
|   `-- cnn_model.py           # PyTorch CNN definition used for MNIST training
|-- scripts/
|   |-- train.py               # Train the PyTorch MNIST model
|   |-- quantize.py            # Export fixed-point weights and biases to Verilog .mem files
|   |-- quantize_adaptive.py   # Export fixed/adaptive quantization variants
|   |-- testmem.py             # Select one MNIST test image and generate cnn.mem
|   |-- sim.py                 # Integer CNN simulator matching the Verilog datapath
|   |-- batch_accuracy.py      # Batch accuracy test for floating-point and quantized inference
|   `-- debug_verify.py        # Detailed software/hardware consistency checks
|-- mem_files/
|   |-- cnn.mem                # 32x32 input image, one byte per line in hex
|   |-- kernel*.mem            # Quantized convolution kernels and biases
|   |-- weights.mem            # Quantized fully connected weights
|   |-- biases.mem             # Quantized fully connected biases
|   |-- fixed/                 # Fixed-shift quantization output
|   `-- adapt/                 # Per-layer adaptive-shift quantization output
|-- weights/
|   `-- mnist_cnn.pth          # Trained PyTorch model checkpoint
|-- Makefile                   # Verilator/NVBoard build flow
`-- test programs.txt          # Small RISC-V assembly programs used during CPU bring-up
```

The current hardware entry point is `vsrc/cpu.v`. The current software entry points are the Python scripts under `scripts/`, which train the reference model, quantize it, prepare MNIST images, and check the fixed-point inference behavior before the generated memory files are used by Verilog.



## Quick Start

### Python Environment

The software side uses PyTorch, TorchVision, NumPy, and Pillow. A typical local setup is:

```bash
pip install torch torchvision numpy pillow
```

Train the CNN model:

```bash
python scripts/train.py
```

Export fixed-point parameters for hardware:

```bash
python scripts/quantize.py
```

Generate one MNIST test image for hardware inference. The optional argument is the MNIST test-set index:

```bash
python scripts/testmem.py 64
```

Run the integer software simulator against the generated `.mem` files:

```bash
python scripts/sim.py --verbose
```

Run a batch accuracy check:

```bash
python scripts/batch_accuracy.py --count 1000
```

### RTL Simulation

For ModelSim-style simulation, compile `vsrc/cpu.v` and `testbench/cpu_tb.v`, start `cpu_tb`, add the desired waveforms, and run until completion. The testbench generates a 100 MHz input clock, releases reset, waits for the CPU program and CNN inference to settle, and prints the decoded prediction from the active-low LED output.

For the NVBoard/Verilator path, make sure `NVBOARD_HOME` points to a valid NVBoard installation, then run:

```bash
make run
```

The Makefile was originally written for a Unix-like Verilator/NVBoard environment, so path tools such as `find`, `mkdir`, and `rm` are expected in that flow.

### FPGA Build Notes

The Vivado constraint file maps the current top-level ports to the Zynq-7020 board:

| Signal | Meaning | Constraint |
| --- | --- | --- |
| `clk` | External input clock | `U18` |
| `sysrst` | Reset input | `N15` |
| `ledr[3:0]` | Active-low binary prediction output | `M14`, `M15`, `K16`, `J16` |

The CNN core currently loads memory files with absolute `$readmemh` paths. If the project is moved to another directory or another machine, update the paths inside `cnn_core` or replace them with project-relative paths before synthesis/simulation.



---



## Versions of the Project

In future development, I will publish several versions of the project from a simple structure to a complicated SoC, and each version will be recorded here.

### v1

This is the first successful implementation of this project, with a CPU and a CNN module combined. Finished in 2026-07-26.

#### Workflow

The v1 workflow is intentionally simple:

1. Train the PyTorch CNN on MNIST resized to `32x32`.
2. Quantize the trained weights and biases into integer `.mem` files.
3. Generate `cnn.mem` from a selected MNIST test image.
4. Let the CPU execute its small built-in RISC-V program.
5. Decode the custom CNN instruction, raise `cnn_en`, and start the accelerator.
6. Run the CNN core with fixed-point arithmetic and block-memory-backed parameters.
7. Show the final predicted digit on four active-low LEDs.

The instruction memory in `cpu.v` currently contains a small GCD program followed by a custom CNN trigger instruction (`FE00707F`) and then `ecall`. This keeps v1 focused on proving CPU-controlled accelerator activation rather than on a complete software loading path.


#### Hardware Design

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


#### Software Infrastructure and Verification

The software infrastructure is used to keep the hardware implementation tied to a reproducible neural-network model:

- `models/cnn_model.py` defines the exact CNN architecture used by training and verification.
- `scripts/train.py` trains the model for MNIST classification and stores the checkpoint in `weights/mnist_cnn.pth`.
- `scripts/quantize.py` exports the current fixed-point format used by `cpu.v`: signed int16 weights, signed int32 biases, and `SHIFT1 = SHIFT2 = SHIFT_FC = 14`.
- `scripts/quantize_adaptive.py` can also produce `mem_files/fixed/` and `mem_files/adapt/` variants for comparing fixed and per-layer shifts.
- `scripts/testmem.py` converts one MNIST test image into `mem_files/cnn.mem` and saves `mem_files/test_image.png` for visual checking.
- `scripts/sim.py` is a hardware-style integer CNN simulator. It reads the same `.mem` files as Verilog and mirrors the fixed-point datapath.
- `scripts/batch_accuracy.py` compares floating-point PyTorch inference, quantized/dequantized weights, and hardware-style integer inference across a batch of MNIST samples.
- `scripts/debug_verify.py` provides deeper checks for bias scaling, fully connected weight layout, and bit-width behavior.

The fixed-point convention used by the current v1 design is:

```text
image_int  = round(image_float * 255)
weight_int = round(weight_float * 2^SHIFT)
bias_int   = round(bias_float * 255 * 2^SHIFT)
output_int = relu((sum(image_int * weight_int) + bias_int) >>> SHIFT)
```

This keeps activations approximately at image scale after each layer while allowing the Verilog implementation to use shift-based requantization instead of division.

## Current Limitations and Future Work

- The CPU and CNN are integrated, but the CPU does not yet manage a complete SoC-level dataflow with a bus, host communication, and dynamic program/image loading.
- The instruction memory and CNN memory initialization are currently static.
- The CNN accelerator is sequential and resource-conscious; later versions can explore more parallelism, DMA-style data movement, and a cleaner memory-mapped accelerator interface.
- The current visible output is a 4-bit LED prediction. Earlier seven-segment display logic is kept in comments, and future versions may restore a richer board-level display or host-side reporting path.

