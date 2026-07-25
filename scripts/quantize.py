import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import torch
import numpy as np
from models.cnn_model import SimpleCNN

# Hardware convention:
#   image_int = round(image_float * 255)
#   weight_int = round(weight_float * 2^SHIFT)
#   bias_int = round(bias_float * 255 * 2^SHIFT)
#   output_int = relu((sum(image_int * weight_int) + bias_int) >>> SHIFT)
# This keeps every ReLU activation approximately at scale 255.
GLOBAL_SHIFT = 14
WEIGHT_SCALE = float(1 << GLOBAL_SHIFT)
ACT_SCALE = 255.0
BIAS_SCALE = ACT_SCALE * WEIGHT_SCALE

model = SimpleCNN()
model.load_state_dict(torch.load('./weights/mnist_cnn.pth', map_location='cpu'))
model.eval()


def quantize_int16(tensor, scale):
    values = tensor.detach().numpy()
    rounded = np.round(values * scale)
    clipped = np.clip(rounded, -32768, 32767).astype(np.int16)
    overflows = int(np.count_nonzero((rounded < -32768) | (rounded > 32767)))
    return clipped, overflows


def quantize_int32(tensor, scale):
    values = tensor.detach().numpy()
    rounded = np.round(values * scale)
    clipped = np.clip(rounded, -2147483648, 2147483647).astype(np.int32)
    overflows = int(np.count_nonzero((rounded < -2147483648) | (rounded > 2147483647)))
    return clipped, overflows


def export_mem(data, filename, bits):
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    if bits == 16:
        data_uint = data.astype(np.uint16)
        fmt = '04X'
    elif bits == 32:
        data_uint = data.astype(np.uint32)
        fmt = '08X'
    else:
        raise ValueError(f'unsupported width: {bits}')

    with open(filename, 'w') as f:
        for val in data_uint.flatten():
            f.write(f'{int(val):{fmt}}\n')
    print(f'  Exported {len(data_uint.flatten())} x int{bits} -> {filename}')


def report_overflow(name, overflows):
    if overflows:
        print(f'  [WARNING] {name}: {overflows} clipped values')


os.makedirs('./mem_files', exist_ok=True)

print('=' * 64)
print(f'  Quantization for hardware fixed-point inference')
print(f'  Weight scale : 2^{GLOBAL_SHIFT} = {int(WEIGHT_SCALE)}')
print(f'  Bias scale   : 255 * 2^{GLOBAL_SHIFT} = {int(BIAS_SCALE)}')
print(f'  Verilog SHIFT parameters must all be {GLOBAL_SHIFT}')
print('=' * 64)

print('\n[Conv1]')
conv1_weight, ov = quantize_int16(model.conv1.weight.data, WEIGHT_SCALE)
report_overflow('Conv1 weight', ov)
export_mem(conv1_weight, './mem_files/kernel1.mem', 16)

conv1_bias, ov = quantize_int32(model.conv1.bias.data, BIAS_SCALE)
report_overflow('Conv1 bias', ov)
export_mem(conv1_bias, './mem_files/kernel1_bias.mem', 32)
print(f'  Bias float={model.conv1.bias.data.item():.6f}, quantized={int(conv1_bias[0])}')

print('\n[Conv2]')
conv2_weight, ov = quantize_int16(model.conv2.weight.data, WEIGHT_SCALE)
report_overflow('Conv2 weight', ov)
export_mem(conv2_weight, './mem_files/kernel2.mem', 16)

conv2_bias, ov = quantize_int32(model.conv2.bias.data, BIAS_SCALE)
report_overflow('Conv2 bias', ov)
export_mem(conv2_bias, './mem_files/kernel2_bias.mem', 32)
print(f'  Bias float={model.conv2.bias.data.item():.6f}, quantized={int(conv2_bias[0])}')

print('\n[FC]')
fc_weight_flat = model.fc.weight.data.T.contiguous().view(-1)
fc_weight, ov = quantize_int16(fc_weight_flat, WEIGHT_SCALE)
report_overflow('FC weight', ov)
export_mem(fc_weight, './mem_files/weights.mem', 16)

fc_bias, ov = quantize_int32(model.fc.bias.data, BIAS_SCALE)
report_overflow('FC bias', ov)
export_mem(fc_bias, './mem_files/biases.mem', 32)
print(f'  Bias range quantized=[{int(fc_bias.min())}, {int(fc_bias.max())}]')

print('\n' + '=' * 64)
print('  DONE - use these Verilog parameters:')
print(f'    Convolution_1:    parameter SHIFT1 = {GLOBAL_SHIFT};')
print(f'    Convolution_2:    parameter SHIFT2 = {GLOBAL_SHIFT};')
print(f'    Fully_Connected:  parameter SHIFT_FC = {GLOBAL_SHIFT};')
print('  Bias memories are now signed 32-bit hex files.')
print('=' * 64)