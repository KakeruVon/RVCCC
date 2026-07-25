"""
Comprehensive verification: compare PyTorch model inference with
hardware-emulated computation using quantized weights.
"""
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import torch
import torch.nn.functional as F
import numpy as np
from torchvision import datasets, transforms
from models.cnn_model import SimpleCNN

# ============================================================
# 1. Load the trained model
# ============================================================
model = SimpleCNN()
model.load_state_dict(torch.load('./weights/mnist_cnn.pth', map_location='cpu'))
model.eval()

# Check for biases in conv layers
print("=" * 60)
print("MODEL PARAMETER CHECK")
print("=" * 60)
print(f"Conv1 has bias: {model.conv1.bias is not None}")
if model.conv1.bias is not None:
    print(f"  Conv1 bias value: {model.conv1.bias.data.item():.6f}")
print(f"Conv2 has bias: {model.conv2.bias is not None}")
if model.conv2.bias is not None:
    print(f"  Conv2 bias value: {model.conv2.bias.data.item():.6f}")
print(f"FC has bias: {model.fc.bias is not None}")

# ============================================================
# 2. Load test image
# ============================================================
transform = transforms.Compose([
    transforms.Resize((32, 32)),
    transforms.ToTensor(),
])
test_dataset = datasets.MNIST(root='./data', train=False, download=True, transform=transform)
image, label = test_dataset[64]
print(f"\nTest image index: 64, Label: {label}")

# ============================================================
# 3. Software model inference (floating point reference)
# ============================================================
with torch.no_grad():
    x = image.unsqueeze(0)
    c1 = model.conv1(x)
    c1_relu = F.relu(c1)
    p1 = F.max_pool2d(c1_relu, 2)
    c2 = model.conv2(p1)
    c2_relu = F.relu(c2)
    p2 = F.max_pool2d(c2_relu, 2)
    fc_in = p2.view(1, -1)
    fc_out = model.fc(fc_in)
    sw_pred = torch.argmax(fc_out, dim=1).item()
    print(f"[SW] Predicted class: {sw_pred}, FC outputs: {fc_out[0]}")

# ============================================================
# 4. Load quantized weights from mem files
# ============================================================
def load_mem(filename, signed=True):
    vals = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                vals.append(int(line, 16))
    arr = np.array(vals, dtype=np.uint16)
    return arr.astype(np.int16) if signed else arr

kernel1_q = load_mem('./mem_files/kernel1.mem').reshape(3, 3)
kernel2_q = load_mem('./mem_files/kernel2.mem').reshape(3, 3)
fc_weights_q_hw = load_mem('./mem_files/weights.mem')  # [360], as loaded by hardware
fc_biases_q_hw = load_mem('./mem_files/biases.mem')     # [10]
cnn_pixels = load_mem('./mem_files/cnn.mem', signed=False).reshape(32, 32)

# ============================================================
# 5. Quantization scheme: unified global power-of-2 scale
# ============================================================
SHIFT = 14
GLOBAL_SCALE = float(1 << SHIFT)  # 16384.0

print(f"\n[Quantization scheme]")
print(f"  Global scale: S = 2^{SHIFT} = {int(GLOBAL_SCALE)}")
print(f"  Global shift: {SHIFT} bits after each layer")
print(f"  All weights/biases quantized with same S = round(float * {int(GLOBAL_SCALE)})")

def quantize_val(tensor):
    """Quantize with global power-of-2 scale."""
    t = tensor.detach().numpy() if hasattr(tensor, 'detach') else np.array(tensor)
    return np.round(t * GLOBAL_SCALE).astype(np.int32)

# Conv biases in quantized form (using global scale)
conv1_bias_q = int(round(model.conv1.bias.data.item() * GLOBAL_SCALE)) if model.conv1.bias is not None else 0
conv2_bias_q = int(round(model.conv2.bias.data.item() * GLOBAL_SCALE)) if model.conv2.bias is not None else 0
print(f"  Conv1 bias (quantized): {conv1_bias_q}")
print(f"  Conv2 bias (quantized): {conv2_bias_q}")

# ============================================================
# 6. HARDWARE-EMULATED INFERENCE
# ============================================================
print("\n" + "=" * 60)
print("HARDWARE-EMULATED INFERENCE (with and without biases)")
print("=" * 60)

def hw_conv2d(input_2d, kernel_2d, bias_q=0, shift=SHIFT):
    """Emulate hardware 3x3 conv2d with ReLU + requantization shift, using int64."""
    h_in, w_in = input_2d.shape
    h_out, w_out = h_in - 2, w_in - 2
    out = np.zeros((h_out, w_out), dtype=np.int64)
    for row in range(h_out):
        for col in range(w_out):
            s = np.int64(0)
            for i in range(3):
                for j in range(3):
                    s += np.int64(input_2d[row + i, col + j]) * np.int64(kernel_2d[i, j])
            s += bias_q
            # ReLU + requantization shift (matching hardware >>> SHIFT)
            out[row, col] = (s >> shift) if s >= 0 else 0
    return out

def hw_maxpool2d(input_2d):
    """Emulate hardware 2x2 max pooling, stride 2."""
    h_in, w_in = input_2d.shape
    h_out, w_out = h_in // 2, w_in // 2
    out = np.zeros((h_out, w_out), dtype=np.int64)
    for row in range(h_out):
        for col in range(w_out):
            r, c = row * 2, col * 2
            out[row, col] = max(
                input_2d[r, c], input_2d[r, c+1],
                input_2d[r+1, c], input_2d[r+1, c+1]
            )
    return out

# --- HW inference WITHOUT conv biases (current hardware) ---
print("\n--- WITHOUT conv biases (current hardware) ---")
hw_c1 = hw_conv2d(cnn_pixels.astype(np.int64), kernel1_q.astype(np.int64), bias_q=0)
hw_p1 = hw_maxpool2d(hw_c1)
hw_c2 = hw_conv2d(hw_p1, kernel2_q.astype(np.int64), bias_q=0)
hw_p2 = hw_maxpool2d(hw_c2)
hw_p2_flat = hw_p2.flatten()

print(f"Conv1 max: {hw_c1.max()}, min: {hw_c1.min()}, non-zero count: {np.count_nonzero(hw_c1)}")
print(f"Conv2 max: {hw_c2.max()}, min: {hw_c2.min()}, non-zero count: {np.count_nonzero(hw_c2)}")

# --- HW inference WITH conv biases (what software actually does) ---
print("\n--- WITH conv biases (correct) ---")
hw_c1_b = hw_conv2d(cnn_pixels.astype(np.int64), kernel1_q.astype(np.int64), bias_q=conv1_bias_q)
hw_p1_b = hw_maxpool2d(hw_c1_b)
hw_c2_b = hw_conv2d(hw_p1_b, kernel2_q.astype(np.int64), bias_q=conv2_bias_q)
hw_p2_b = hw_maxpool2d(hw_c2_b)
hw_p2_flat_b = hw_p2_b.flatten()

print(f"Conv1 (w/bias) max: {hw_c1_b.max()}, non-zero count: {np.count_nonzero(hw_c1_b)}")
print(f"Conv2 (w/bias) max: {hw_c2_b.max()}, non-zero count: {np.count_nonzero(hw_c2_b)}")

# ============================================================
# 7. FC weight layout check
# ============================================================
print("\n" + "=" * 60)
print("FC WEIGHT LAYOUT ANALYSIS")
print("=" * 60)

fc_w_pytorch = model.fc.weight.data.numpy()  # [10, 36]

# Current HW mem file layout: pytorch_weight.flatten() (no transpose)
fc_w_current_layout = fc_w_pytorch.flatten()

# Expected HW layout: TRANSPOSED - grouped by input position
fc_w_expected_layout = fc_w_pytorch.T.flatten()  # [36, 10].T → same as .flatten() after transpose

# Quantize both layouts for comparison (using global power-of-2 scale)
def quantize_arr(arr):
    return np.round(arr * GLOBAL_SCALE).astype(np.int16)

fc_w_q_current = quantize_arr(fc_w_current_layout)
fc_w_q_expected = quantize_arr(fc_w_expected_layout)

match_current = np.array_equal(fc_weights_q_hw, fc_w_q_current)
match_expected = np.array_equal(fc_weights_q_hw, fc_w_q_expected)

print(f"Mem file matches current layout (NO transpose): {match_current}")
print(f"Mem file matches expected layout (TRANSPOSED): {match_expected}")
if match_current:
    print("*** BUG: FC weights are NOT transposed! Hardware interprets them incorrectly. ***")

# ============================================================
# 8. FC output comparison
# ============================================================
print("\n" + "=" * 60)
print("FC OUTPUT COMPARISON (using HW inference with biases)")
print("=" * 60)

def compute_fc(pool_flat, weights_q, biases_q):
    """Compute FC output with given weight layout (hardware-emulated: 6 rows, shift per row)."""
    out = np.zeros(10, dtype=np.int64)
    for i in range(10):  # output neuron
        acc = np.int64(0)
        for row in range(6):
            row_sum = np.int64(0)
            for j in range(6):
                pos = row * 6 + j
                wt_idx = 10 * pos + i
                row_sum += np.int64(pool_flat[pos]) * np.int64(weights_q[wt_idx])
            if row == 5:
                row_sum += np.int64(biases_q[i])
            # Shift per row then accumulate (matching hardware)
            acc += np.int64(np.int32(row_sum >> SHIFT))
        out[i] = acc
    return out

# FC with current layout (buggy)
hw_fc_current = compute_fc(hw_p2_flat_b, fc_weights_q_hw, fc_biases_q_hw)
# FC with correct (transposed) layout
hw_fc_correct = compute_fc(hw_p2_flat_b, fc_w_q_expected, fc_biases_q_hw)

sw_fc = fc_out[0].numpy()

print(f"{'Neuron':<8} {'SW (float)':<16} {'HW-current':<18} {'HW-correct':<18}")
print("-" * 62)
for i in range(10):
    hw_cur = hw_fc_current[i]
    hw_cor = hw_fc_correct[i]
    print(f"{i:<8} {sw_fc[i]:<16.6f} {hw_cur:<18} {hw_cor:<18}")

sw_argmax = np.argmax(sw_fc)
hw_cur_argmax = np.argmax(hw_fc_current)
hw_cor_argmax = np.argmax(hw_fc_correct)
print(f"\nSW argmax:               {sw_argmax}")
print(f"HW-current (no transpose): {hw_cur_argmax}")
print(f"HW-correct (transposed):   {hw_cor_argmax}")

# ============================================================
# 9. Check bit-width issues
# ============================================================
print("\n" + "=" * 60)
print("BIT-WIDTH / OVERFLOW ANALYSIS  (with >>> SHIFT requantization)")
print("=" * 60)

# After requantization shift, values are much smaller
# Check if conv1 outputs fit in 16-bit (for Pool1 buffer)
max_c1 = hw_c1_b.max()
min_c1 = hw_c1_b.min()
print(f"Conv1 output range (after >>>{SHIFT}): [{min_c1}, {max_c1}]")
print(f"  Fits in int16 ({-32768} to {32767}): {min_c1 >= -32768 and max_c1 <= 32767}")

# Check if conv2 accumulation fits in 32-bit after shift
pool1_max = hw_p1_b.max()
pool1_min = hw_p1_b.min()
k2_max = np.max(np.abs(kernel2_q))
max_conv2_product = np.int64(pool1_max) * np.int64(k2_max) if pool1_max > abs(pool1_min) else abs(np.int64(pool1_min)) * np.int64(k2_max)
max_conv2_sum = max_conv2_product * 9 + abs(conv2_bias_q)
print(f"Pool1 output range (after >>>{SHIFT}): [{pool1_min}, {pool1_max}]")
print(f"  Fits in int16 ({-32768} to {32767}): {pool1_min >= -32768 and pool1_max <= 32767}")
print(f"Conv2 max product: {max_conv2_product}, max sum (9 products + bias): {max_conv2_sum}")
print(f"  Conv2 64-bit acc fits in int64: {max_conv2_sum < (1<<63)}")

# Check FC accumulation overflow (now per-row shift keeps values bounded)
fc_input_max = hw_p2_b.max()
fc_weight_max = np.max(np.abs(fc_w_q_expected))
max_fc_product = np.int64(fc_input_max) * np.int64(fc_weight_max)
max_fc_sum = max_fc_product * 6  # 6 inputs per row
print(f"FC input max: {fc_input_max}, FC weight max: {fc_weight_max}")
print(f"FC max per-row accumulation (6 products): {max_fc_sum}")
print(f"  Fits in int64 after shift: {max_fc_sum < (1<<63)}")

# ============================================================
# 10. Summary
# ============================================================
print("\n" + "=" * 60)
print("FINDINGS SUMMARY")
print("=" * 60)

issues = []

# Issue 1: Missing conv biases
if model.conv1.bias is not None and model.conv1.bias.data.item() != 0:
    issues.append(f"1. MISSING CONV1 BIAS: bias={model.conv1.bias.data.item():.4f} not exported/implemented in hardware")
if model.conv2.bias is not None and model.conv2.bias.data.item() != 0:
    issues.append(f"2. MISSING CONV2 BIAS: bias={model.conv2.bias.data.item():.4f} not exported/implemented in hardware")

# Issue 3: FC weight layout
if match_current and not match_expected:
    issues.append("3. FC WEIGHT LAYOUT ERROR: weights not transposed; hardware reads wrong input-output mappings")

# Issue 4: Bit width (with requantization shifts, should be safe)
if min_c1 < -32768 or max_c1 > 32767:
    issues.append(f"4. POOL1 BUFFER OVERFLOW: conv1 outputs [{min_c1},{max_c1}] exceed 16-bit range")
if max_conv2_sum >= (1<<63):
    issues.append(f"5. CONV2 ACCUMULATION OVERFLOW: sum={max_conv2_sum} exceeds 64-bit range")

# Issue 5: Requantization scheme
issues.append("6. REQUANTIZATION: global S=2^14, SHIFT=14 applied after each layer (Conv1/Conv2/FC)")

# Issue 6: testmem.py supports command-line argument
issues.append("7. testmem.py accepts image index as command-line argument (default 0)")

for issue in issues:
    print(issue)

if not issues:
    print("No issues found.")
