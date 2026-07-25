#!/usr/bin/env python3
"""
CNN Inference Simulator - simulates the cnn_core module in cpu.v
Reads .mem files and performs integer-only inference matching the Verilog hardware.

Usage:
    python scripts/sim.py [--image MEMFILE] [--verbose]

Default input image: mem_files/cnn.mem
"""

import os
import sys
import argparse
import numpy as np

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
MEM_DIR = os.path.join(PROJECT_ROOT, "mem_files")


# ---------------------------------------------------------------------------
# Per-layer requantization shifts (must match cpu.v and quantize.py)
# ---------------------------------------------------------------------------
# Each layer uses its optimal power-of-2 scale:
#   S_layer = 2^SHIFT_layer,  weights = round(float_w * S_layer)
#
# For this model, all layers are constrained to SHIFT=14:
#   Conv1: S=16384 (weight max 1.01 -> 1.01*32768=33084 > 32767 overflow)
#   Conv2: S=16384 (bias 1.73 -> 1.73*32768=56710 > 32767 overflow)
#   FC:    S=16384 (weight max 1.11 -> 1.11*32768=36212 > 32767 overflow)
# ---------------------------------------------------------------------------
SHIFT1   = 14  # Conv1 requantization shift (S = 2^14 = 16384)
SHIFT2   = 14  # Conv2 requantization shift (S = 2^14 = 16384)
SHIFT_FC = 14  # FC    requantization shift (S = 2^14 = 16384)

# ---------------------------------------------------------------------------
# Hardware-accurate 32-bit signed truncation
# ---------------------------------------------------------------------------
def as_int32(value: int) -> int:
    """
    Truncate an arbitrary-width integer to 32-bit signed.
    Matches Verilog behaviour when a wide register (e.g. 64-bit) is
    assigned to a 32-bit part-select field.

    Verilog reference:
        reg signed [63:0] conv_output;
        conv_data_out_2[k*32+31 -:32] <= (conv_output>=0) ? conv_output : 0;
        // 64-bit conv_output truncated to lower 32 bits
    """
    mask = 0xFFFFFFFF
    truncated = value & mask
    if truncated >= 0x80000000:
        truncated -= 0x100000000  # sign-extend back to negative
    return truncated


# ---------------------------------------------------------------------------
# .mem file reader (Verilog $readmemh format)
# ---------------------------------------------------------------------------
def read_mem_hex(filename: str, bits: int = 16, signed: bool = True) -> np.ndarray:
    """
    Read a .mem file in Verilog $readmemh format (one hex value per line).

    Parameters
    ----------
    filename : str
        Path to .mem file
    bits : int
        Bit width for sign extension
    signed : bool
        If True, interpret unsigned hex as 2's-complement signed int

    Returns
    -------
    np.ndarray (dtype=int32) of raw integer values
    """
    values = []
    with open(filename, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                values.append(int(line, 16))

    arr = np.array(values, dtype=np.int64)

    if signed and bits > 0:
        sign_bit = 1 << (bits - 1)
        neg = (arr & sign_bit) != 0
        arr[neg] = arr[neg] - (1 << bits)

    return arr


# ---------------------------------------------------------------------------
# CNN Inference Core
# ---------------------------------------------------------------------------
def cnn_inference(
    cnn_mem_path: str = None,
    mem_dir: str = None,
) -> dict:
    """
    Run the full CNN inference pipeline, matching the Verilog cnn_core
    module behaviour exactly.

    Pipeline stages (matching cnn_core submodules):
        Data_Buffer    -> 32x32 input image (sliding window)
        Convolution_1  -> 3x3 conv + bias + ReLU -> 30x30  (32-bit safe)
        Max_Pooling_1  -> 2x2 max pool, stride=2 -> 15x15
        Convolution_2  -> 3x3 conv + bias + ReLU -> 13x13  (64-bit acc, 32-bit out)
        Max_Pooling_2  -> 2x2 max pool, stride=2 -> 6x6
        Fully_Connected -> 36->10 (6 rows, each row truncated to 32-bit)
        predicted_class -> argmax over 64-bit accumulated buffer

    Returns
    -------
    dict with keys:
        input, conv1, pool1, conv2_raw, conv2, pool2, fc_rows, fc, predicted_class
    """
    if mem_dir is None:
        mem_dir = MEM_DIR
    if cnn_mem_path is None:
        cnn_mem_path = os.path.join(mem_dir, "cnn.mem")

    # ===================================================================
    # 1. Load all .mem parameter files
    # ===================================================================

    # Input image: 32x32, 8-bit unsigned (0-255)
    input_img = read_mem_hex(cnn_mem_path, bits=8, signed=False)
    if len(input_img) != 1024:
        raise ValueError(
            f"cnn.mem must contain 1024 values (32x32), got {len(input_img)}"
        )
    input_img = input_img.reshape(32, 32).astype(np.int32)

    # Conv1: 3x3 kernel is 16-bit signed, bias is 32-bit signed
    kernel1 = read_mem_hex(os.path.join(mem_dir, "kernel1.mem"), bits=16, signed=True)
    kernel1 = kernel1.reshape(3, 3).astype(np.int32)
    bias1_val = int(
        read_mem_hex(os.path.join(mem_dir, "kernel1_bias.mem"), bits=32, signed=True)[0]
    )

    # Conv2: 3x3 kernel is 16-bit signed, bias is 32-bit signed
    kernel2 = read_mem_hex(os.path.join(mem_dir, "kernel2.mem"), bits=16, signed=True)
    kernel2 = kernel2.reshape(3, 3).astype(np.int32)
    bias2_val = int(
        read_mem_hex(os.path.join(mem_dir, "kernel2_bias.mem"), bits=32, signed=True)[0]
    )

    # FC: 360 weights are 16-bit signed; 10 biases are 32-bit signed
    # Hardware layout: fc_weights[10 * input_pos + output_neuron]
    # i.e. for each input position k=0..35, 10 output-neuron weights stored contiguously
    fc_w = read_mem_hex(os.path.join(mem_dir, "weights.mem"), bits=16, signed=True)
    if len(fc_w) != 360:
        raise ValueError(
            f"weights.mem must contain 360 values (36x10), got {len(fc_w)}"
        )
    fc_weights = fc_w.reshape(36, 10).astype(np.int64)  # [input_pos, output]

    fc_b = read_mem_hex(os.path.join(mem_dir, "biases.mem"), bits=32, signed=True)
    fc_biases = fc_b.astype(np.int64)  # [10]

    # ===================================================================
    # 2. Convolution 1: 3x3 valid conv + bias + ReLU + SHIFT -> 30x30
    #    Hardware: 32-bit acc -> ReLU -> >>> SHIFT1 -> 32-bit output
    # ===================================================================
    H1, W1 = 30, 30
    conv1_out = np.zeros((H1, W1), dtype=np.int32)

    for r in range(H1):
        for c in range(W1):
            acc = 0
            for i in range(3):
                for j in range(3):
                    acc += int(input_img[r + i, c + j]) * int(kernel1[i, j])
            acc += bias1_val
            # ReLU + requantization shift (matching hardware >>> SHIFT1)
            conv1_out[r, c] = max(0, acc) >> SHIFT1

    # ===================================================================
    # 3. Max Pooling 1: 2x2, stride=2 -> 15x15
    # ===================================================================
    H1p, W1p = 15, 15
    pool1_out = np.zeros((H1p, W1p), dtype=np.int32)

    for r in range(H1p):
        for c in range(W1p):
            r0, c0 = r * 2, c * 2
            pool1_out[r, c] = int(np.max(conv1_out[r0:r0 + 2, c0:c0 + 2]))

    # ===================================================================
    # 4. Convolution 2: 3x3 valid conv + bias + ReLU + SHIFT -> 13x13
    #    Hardware: conv_output is reg signed [63:0] (64-bit);
    #    ReLU + >>> SHIFT2 on full 64-bit; then 32-bit part-select truncation.
    #    Python: full-precision acc -> ReLU -> shift -> as_int32() truncation
    # ===================================================================
    H2, W2 = 13, 13
    conv2_out = np.zeros((H2, W2), dtype=np.int32)
    conv2_raw = np.zeros((H2, W2), dtype=np.int64)  # pre-truncation (debug)

    for r in range(H2):
        for c in range(W2):
            acc = 0  # Python int (acts like Verilog 64-bit)
            for i in range(3):
                for j in range(3):
                    acc += int(pool1_out[r + i, c + j]) * int(kernel2[i, j])
            acc += bias2_val
            conv2_raw[r, c] = acc
            # ReLU on full-width, shift, then truncate to 32-bit (matching hardware)
            if acc >= 0:
                conv2_out[r, c] = as_int32(acc >> SHIFT2)
            else:
                conv2_out[r, c] = 0

    # ===================================================================
    # 5. Max Pooling 2: 2x2, stride=2 -> 6x6
    #    13/2 = 6 (floor; last row/col dropped, matching hardware)
    # ===================================================================
    H2p, W2p = 6, 6
    pool2_out = np.zeros((H2p, W2p), dtype=np.int32)

    for r in range(H2p):
        for c in range(W2p):
            r0, c0 = r * 2, c * 2
            pool2_out[r, c] = int(np.max(conv2_out[r0:r0 + 2, c0:c0 + 2]))

    # ===================================================================
    # 6. Fully Connected: 36 -> 10
    #    Hardware behaviour:
    #      - pool_out_valid_2 fires once per row (6 inputs)
    #      - FC computes 10 partial sums per row (sum over j=0..5)
    #      - Row 5 (last) adds bias
    #      - Each row: 64-bit sum >>> SHIFT -> 32-bit truncation (fc_data_out)
    #      - predicted_class accumulates these 32-bit values into 64-bit buffer
    #    Simulation: 6-row loop -> per-row shift + 32-bit trunc -> 64-bit accumulate
    # ===================================================================
    pool2_flat = pool2_out.flatten().astype(np.int64)  # [36]

    fc_rows = np.zeros((6, 10), dtype=np.int32)      # per-row partial sums (32-bit)
    fc_accum = np.zeros(10, dtype=np.int64)           # predicted_class buffer (64-bit)

    for row in range(6):
        for i in range(10):
            row_sum = 0  # Python int (Verilog 64-bit sum)
            for j in range(6):
                k = row * 6 + j  # input index 0..35
                row_sum += int(pool2_flat[k]) * int(fc_weights[k, i])
            if row == 5:
                row_sum += int(fc_biases[i])
            # Shift 64-bit sum before 32-bit truncation (matching hardware >>> SHIFT_FC)
            fc_rows[row, i] = as_int32(row_sum >> SHIFT_FC)
            # predicted_class accumulates in 64-bit
            fc_accum[i] += as_int32(row_sum >> SHIFT_FC)

    # ===================================================================
    # 7. Argmax -> predicted class
    # ===================================================================
    predicted_class = int(np.argmax(fc_accum))

    return {
        "input":            input_img.astype(np.uint8),
        "conv1":            conv1_out,
        "pool1":            pool1_out,
        "conv2_raw":        conv2_raw,
        "conv2":            conv2_out,
        "pool2":            pool2_out,
        "fc_rows":          fc_rows,
        "fc":               fc_accum,
        "predicted_class":  predicted_class,
    }


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="CNN Inference Simulator - Verilog cnn_core behavioural model"
    )
    parser.add_argument(
        "--image", "-i", default=None,
        help="Input image .mem file (default: mem_files/cnn.mem)",
    )
    parser.add_argument(
        "--mem-dir", default=None,
        help="Directory containing .mem files (default: mem_files/)",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Print intermediate layer outputs",
    )
    parser.add_argument(
        "--full-conv", action="store_true",
        help="In verbose mode, print full 30x30/15x15 matrices (default: corners only)",
    )
    args = parser.parse_args()

    mem_dir = args.mem_dir or MEM_DIR
    cnn_path = args.image or os.path.join(mem_dir, "cnn.mem")

    if not os.path.isfile(cnn_path):
        print(f"Error: input image file not found: {cnn_path}")
        sys.exit(1)

    # Configure numpy print options for verbose mode
    if args.verbose:
        if args.full_conv:
            np.set_printoptions(threshold=99999, linewidth=200, edgeitems=30)
        else:
            np.set_printoptions(threshold=100, linewidth=120, edgeitems=3)

    # Run inference
    print("=" * 64)
    print("  CNN Inference Simulator - Verilog cnn_core behavioural model")
    print("=" * 64)
    print(f"  Input image : {cnn_path}")
    print(f"  Param dir   : {mem_dir}")
    print()

    results = cnn_inference(cnn_mem_path=cnn_path, mem_dir=mem_dir)

    print(f"  >>> Predicted class: {results['predicted_class']} <<<")
    print()

    # Verbose output
    if args.verbose:
        sep = "-" * 64

        print(sep)
        print("[Input Image] 32x32, uint8  (0=black, 255=white)")
        print(sep)
        print(results["input"])
        print(f"  non-zero pixels: {np.count_nonzero(results['input'])}")
        print()

        print(sep)
        print("[Conv1 + ReLU] 30x30, int32")
        print(sep)
        print(results["conv1"])
        print(f"  min={results['conv1'].min()}, max={results['conv1'].max()}")
        print()

        print(sep)
        print("[MaxPool1] 15x15, int32")
        print(sep)
        print(results["pool1"])
        print(f"  min={results['pool1'].min()}, max={results['pool1'].max()}")
        print()

        print(sep)
        print("[Conv2 + ReLU] 13x13, int32  (64-bit acc -> ReLU -> 32-bit trunc)")
        print(sep)
        print(results["conv2"])
        print(f"  min={results['conv2'].min()}, max={results['conv2'].max()}")
        # Detect overflow: positive 64-bit values truncated to negative 32-bit
        overflow_mask = (results["conv2_raw"] > 0) & (results["conv2"] < 0)
        n_overflows = np.count_nonzero(overflow_mask)
        if n_overflows > 0:
            print(f"  [!] trunc overflow: {n_overflows} positions have "
                  f"64-bit positive truncated to 32-bit negative")
        print()

        print(sep)
        print("[MaxPool2] 6x6, int32")
        print(sep)
        print(results["pool2"])
        print(f"  min={results['pool2'].min()}, max={results['pool2'].max()}")
        print()

        print(sep)
        print("[FC Row Partial Sums] 6 rows x 10, int32  (each row truncated to 32-bit)")
        print(sep)
        for row in range(6):
            print(f"  row {row}: {list(results['fc_rows'][row])}")
        print()

        print(sep)
        print("[FC Final Output] 10, int64  (predicted_class buffer accumulated)")
        print(sep)
        fc_vals = results["fc"]
        fc_min = int(fc_vals.min())
        fc_max = int(fc_vals.max())
        fc_range = max(1, fc_max - fc_min)
        for i, val in enumerate(fc_vals):
            val_i = int(val)
            if fc_range > 0:
                bar_len = max(0, int((val_i - fc_min) * 40 / fc_range))
            else:
                bar_len = 0
            bar = "#" * bar_len
            marker = " <-- predicted" if i == results["predicted_class"] else ""
            print(f"  class {i}: {val_i:>14d}  {bar}{marker}")
        print()

    print(f"  Inference complete! Predicted digit = {results['predicted_class']}")
    print("=" * 64)


if __name__ == "__main__":
    main()
