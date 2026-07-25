#!/usr/bin/env python3
"""Export fixed/adaptive quantized .mem files with corrected 32-bit bias scale."""

import argparse
import os
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import numpy as np
import torch
from models.cnn_model import SimpleCNN

MEM_DIR = './mem_files'
ACT_SCALE = 255.0


def max_abs(tensor):
    arr = tensor.detach().cpu().numpy() if hasattr(tensor, 'detach') else np.asarray(tensor)
    return float(np.max(np.abs(arr)))


def best_weight_shift(tensor):
    m = max_abs(tensor)
    if m == 0:
        return 16
    best = 0
    for shift in range(0, 24):
        if m * float(1 << shift) > 32767:
            break
        best = shift
    return best


def quantize_int16(tensor, shift):
    scale = float(1 << shift)
    arr = tensor.detach().cpu().numpy() if hasattr(tensor, 'detach') else np.asarray(tensor)
    rounded = np.round(arr * scale)
    clipped = np.clip(rounded, -32768, 32767).astype(np.int16)
    overflow = int(np.count_nonzero((rounded < -32768) | (rounded > 32767)))
    return clipped, overflow


def quantize_bias_int32(tensor, shift):
    scale = ACT_SCALE * float(1 << shift)
    arr = tensor.detach().cpu().numpy() if hasattr(tensor, 'detach') else np.asarray(tensor)
    rounded = np.round(arr * scale)
    clipped = np.clip(rounded, -2147483648, 2147483647).astype(np.int32)
    overflow = int(np.count_nonzero((rounded < -2147483648) | (rounded > 2147483647)))
    return clipped, overflow


def export_mem(data, filename, bits):
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    if bits == 16:
        data_uint = data.astype(np.uint16)
        fmt = '04X'
    elif bits == 32:
        data_uint = data.astype(np.uint32)
        fmt = '08X'
    else:
        raise ValueError(bits)
    with open(filename, 'w') as f:
        for val in data_uint.flatten():
            f.write(f'{int(val):{fmt}}\n')
    print(f'  Exported {len(data_uint.flatten())} x int{bits} -> {filename}')


def export_scheme(model, scheme_name, shifts, out_dir):
    s1, s2, sf = shifts['conv1'], shifts['conv2'], shifts['fc']
    print(f'\n--- {scheme_name} ---')
    print(f'  SHIFT=(conv1:{s1}, conv2:{s2}, fc:{sf})')
    print('  Bias scale per layer: 255 * 2^SHIFT, stored as signed 32-bit')

    w1, ov = quantize_int16(model.conv1.weight.data, s1)
    if ov: print(f'  [WARN] conv1 weight clipped: {ov}')
    export_mem(w1, os.path.join(out_dir, 'kernel1.mem'), 16)
    b1, ov = quantize_bias_int32(model.conv1.bias.data, s1)
    if ov: print(f'  [WARN] conv1 bias clipped: {ov}')
    export_mem(b1, os.path.join(out_dir, 'kernel1_bias.mem'), 32)

    w2, ov = quantize_int16(model.conv2.weight.data, s2)
    if ov: print(f'  [WARN] conv2 weight clipped: {ov}')
    export_mem(w2, os.path.join(out_dir, 'kernel2.mem'), 16)
    b2, ov = quantize_bias_int32(model.conv2.bias.data, s2)
    if ov: print(f'  [WARN] conv2 bias clipped: {ov}')
    export_mem(b2, os.path.join(out_dir, 'kernel2_bias.mem'), 32)

    wf, ov = quantize_int16(model.fc.weight.data.T.contiguous(), sf)
    if ov: print(f'  [WARN] fc weight clipped: {ov}')
    export_mem(wf, os.path.join(out_dir, 'weights.mem'), 16)
    bf, ov = quantize_bias_int32(model.fc.bias.data, sf)
    if ov: print(f'  [WARN] fc bias clipped: {ov}')
    export_mem(bf, os.path.join(out_dir, 'biases.mem'), 32)


def main():
    parser = argparse.ArgumentParser(description='Adaptive fixed-point .mem exporter')
    parser.add_argument('--export', choices=['fixed', 'adapt', 'all'], default='all')
    args = parser.parse_args()

    model = SimpleCNN()
    model.load_state_dict(torch.load('./weights/mnist_cnn.pth', map_location='cpu'))
    model.eval()

    sw1 = best_weight_shift(model.conv1.weight.data)
    sw2 = best_weight_shift(model.conv2.weight.data)
    swf = best_weight_shift(model.fc.weight.data)
    fixed = min(sw1, sw2, swf)

    print('=' * 72)
    print('  QUANTIZATION ANALYSIS - weights int16, bias int32')
    print('=' * 72)
    print(f'  Conv1 weight max={max_abs(model.conv1.weight.data):.6f}, best SHIFT={sw1}')
    print(f'  Conv2 weight max={max_abs(model.conv2.weight.data):.6f}, best SHIFT={sw2}')
    print(f'  FC    weight max={max_abs(model.fc.weight.data):.6f}, best SHIFT={swf}')
    print(f'  Fixed SHIFT={fixed}')

    if args.export in ('fixed', 'all'):
        export_scheme(model, f'FIXED SHIFT={fixed}', {'conv1': fixed, 'conv2': fixed, 'fc': fixed}, f'{MEM_DIR}/fixed')
    if args.export in ('adapt', 'all'):
        export_scheme(model, f'ADAPT SHIFT={sw1}/{sw2}/{swf}', {'conv1': sw1, 'conv2': sw2, 'fc': swf}, f'{MEM_DIR}/adapt')

    print('\nFor cpu.v, use matching SHIFT parameters for the exported folder you copy to mem_files/.')


if __name__ == '__main__':
    main()