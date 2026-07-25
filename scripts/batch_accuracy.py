#!/usr/bin/env python3
"""
Batch accuracy test for the MNIST CNN fixed-point hardware model.

Schemes:
  SW-FLOAT    : original PyTorch float model
  QDQ-WEIGHTS : weights are quantized to int16 then dequantized; activations stay float
  HW-FIXED    : hardware-style integer inference, one common weight shift
  HW-ADAPT    : hardware-style integer inference, per-layer weight shifts

Hardware convention used by HW-*:
  image_int = round(image_float * 255)
  weight_int = round(weight_float * 2^SHIFT)
  bias_int = round(bias_float * 255 * 2^SHIFT)   # signed 32-bit
  y_int = relu((sum(x_int * weight_int) + bias_int) >>> SHIFT)

With SHIFT equal to the weight quantization shift, activations remain at roughly
scale 255 after each layer.
"""

import argparse
import os
import sys
import time
from collections import defaultdict

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import numpy as np
import torch
from torchvision import datasets, transforms

from models.cnn_model import SimpleCNN

DEFAULT_COUNT = 1000
ACT_SCALE = 255.0


def as_int32(value):
    value = int(value) & 0xFFFFFFFF
    return value - 0x100000000 if value >= 0x80000000 else value


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
    return np.clip(np.round(arr * scale), -32768, 32767).astype(np.int16)


def quantize_bias_int32(tensor, shift):
    scale = ACT_SCALE * float(1 << shift)
    arr = tensor.detach().cpu().numpy() if hasattr(tensor, 'detach') else np.asarray(tensor)
    return np.clip(np.round(arr * scale), -2147483648, 2147483647).astype(np.int32)


def image_to_u8(image_tensor):
    return (image_tensor.squeeze().numpy() * 255.0).round().clip(0, 255).astype(np.uint8)


def sw_float_infer(model, image_tensor):
    with torch.no_grad():
        out = model(image_tensor.unsqueeze(0))[0]
    return int(torch.argmax(out).item()), out.detach().numpy()


def qdq_weight_infer(model, image_tensor, qparams):
    # A pure diagnostic: only weight quantization error, no integer activation shifts.
    with torch.no_grad():
        x = image_tensor.unsqueeze(0)
        w1 = torch.from_numpy(qparams['k1'].astype(np.float32) / float(1 << qparams['shift1'])).view(1, 1, 3, 3)
        b1 = torch.from_numpy(qparams['b1_float'].astype(np.float32))
        w2 = torch.from_numpy(qparams['k2'].astype(np.float32) / float(1 << qparams['shift2'])).view(1, 1, 3, 3)
        b2 = torch.from_numpy(qparams['b2_float'].astype(np.float32))
        wf = torch.from_numpy((qparams['fc_w'].astype(np.float32) / float(1 << qparams['shift_fc'])).T.copy())
        bf = torch.from_numpy(qparams['fc_b_float'].astype(np.float32))

        x = torch.relu(torch.nn.functional.conv2d(x, w1, b1))
        x = torch.nn.functional.max_pool2d(x, 2)
        x = torch.relu(torch.nn.functional.conv2d(x, w2, b2))
        x = torch.nn.functional.max_pool2d(x, 2)
        x = x.view(1, -1)
        out = torch.nn.functional.linear(x, wf, bf)[0]
    return int(torch.argmax(out).item()), out.numpy()


def infer_hw(image_u8, qp):
    img = image_u8.astype(np.int32)

    conv1 = np.zeros((30, 30), dtype=np.int32)
    for r in range(30):
        for c in range(30):
            acc = 0
            for i in range(3):
                for j in range(3):
                    acc += int(img[r + i, c + j]) * int(qp['k1'][i, j])
            acc += int(qp['b1'][0])
            conv1[r, c] = as_int32(acc >> qp['shift1']) if acc >= 0 else 0

    pool1 = np.zeros((15, 15), dtype=np.int32)
    for r in range(15):
        for c in range(15):
            pool1[r, c] = int(np.max(conv1[r * 2:r * 2 + 2, c * 2:c * 2 + 2]))

    conv2 = np.zeros((13, 13), dtype=np.int32)
    for r in range(13):
        for c in range(13):
            acc = 0
            for i in range(3):
                for j in range(3):
                    acc += int(pool1[r + i, c + j]) * int(qp['k2'][i, j])
            acc += int(qp['b2'][0])
            conv2[r, c] = as_int32(acc >> qp['shift2']) if acc >= 0 else 0

    pool2 = np.zeros((6, 6), dtype=np.int32)
    for r in range(6):
        for c in range(6):
            pool2[r, c] = int(np.max(conv2[r * 2:r * 2 + 2, c * 2:c * 2 + 2]))

    flat = pool2.flatten().astype(np.int64)
    fc = np.zeros(10, dtype=np.int64)
    for row in range(6):
        for out_idx in range(10):
            row_sum = 0
            for j in range(6):
                k = row * 6 + j
                row_sum += int(flat[k]) * int(qp['fc_w'][k, out_idx])
            if row == 5:
                row_sum += int(qp['fc_b'][out_idx])
            fc[out_idx] += as_int32(row_sum >> qp['shift_fc'])

    return int(np.argmax(fc)), fc


def make_qparams(model, mode):
    if mode == 'fixed':
        shift = min(
            best_weight_shift(model.conv1.weight.data),
            best_weight_shift(model.conv2.weight.data),
            best_weight_shift(model.fc.weight.data),
        )
        s1 = s2 = sf = shift
        name = 'HW-FIXED'
    elif mode in ('adapt', 'exact'):
        s1 = best_weight_shift(model.conv1.weight.data)
        s2 = best_weight_shift(model.conv2.weight.data)
        sf = best_weight_shift(model.fc.weight.data)
        name = 'QDQ-WEIGHTS' if mode == 'exact' else 'HW-ADAPT'
    else:
        raise ValueError(mode)

    return name, {
        'shift1': s1,
        'shift2': s2,
        'shift_fc': sf,
        'k1': quantize_int16(model.conv1.weight.data, s1).reshape(3, 3),
        'b1': quantize_bias_int32(model.conv1.bias.data, s1),
        'k2': quantize_int16(model.conv2.weight.data, s2).reshape(3, 3),
        'b2': quantize_bias_int32(model.conv2.bias.data, s2),
        'fc_w': quantize_int16(model.fc.weight.data.T.contiguous(), sf).reshape(36, 10),
        'fc_b': quantize_bias_int32(model.fc.bias.data, sf),
        'b1_float': model.conv1.bias.detach().cpu().numpy(),
        'b2_float': model.conv2.bias.detach().cpu().numpy(),
        'fc_b_float': model.fc.bias.detach().cpu().numpy(),
    }


def main():
    parser = argparse.ArgumentParser(description='Batch accuracy test for quantized CNN inference')
    parser.add_argument('--count', '-n', type=int, default=DEFAULT_COUNT)
    parser.add_argument('--start', type=int, default=0)
    parser.add_argument('--analysis', '-a', action='store_true')
    parser.add_argument('--schemes', nargs='+', default=['fixed', 'adapt', 'exact'], choices=['fixed', 'adapt', 'exact'])
    args = parser.parse_args()

    n_test = min(args.count, 10000 - args.start)
    print('=' * 72)
    print('  BATCH ACCURACY TEST - corrected bias scale / 32-bit bias')
    print('=' * 72)
    print(f'  Test images: {n_test} (from index {args.start})')

    model = SimpleCNN()
    model.load_state_dict(torch.load('./weights/mnist_cnn.pth', map_location='cpu'))
    model.eval()

    transform = transforms.Compose([
        transforms.Resize((32, 32)),
        transforms.ToTensor(),
    ])
    test_dataset = datasets.MNIST(root='./data', train=False, download=True, transform=transform)

    qparams = {}
    scheme_names = {}
    for scheme in args.schemes:
        display_name, qp = make_qparams(model, scheme)
        scheme_names[scheme] = display_name
        qparams[scheme] = qp
        print(f"  {display_name}: SHIFT=({qp['shift1']}, {qp['shift2']}, {qp['shift_fc']})")

    correct = defaultdict(int)
    confusion = {s: np.zeros((10, 10), dtype=np.int32) for s in args.schemes}
    mismatches = defaultdict(list)
    start_time = time.time()

    for step, idx in enumerate(range(args.start, args.start + n_test), start=1):
        image_tensor, label = test_dataset[idx]
        sw_pred, _ = sw_float_infer(model, image_tensor)
        correct['SW-FLOAT'] += int(sw_pred == label)
        image_u8 = image_to_u8(image_tensor)

        for scheme in args.schemes:
            if scheme == 'exact':
                pred, out = qdq_weight_infer(model, image_tensor, qparams[scheme])
            else:
                pred, out = infer_hw(image_u8, qparams[scheme])
            correct[scheme] += int(pred == label)
            confusion[scheme][int(label), pred] += 1
            if pred != label and len(mismatches[scheme]) < 10:
                mismatches[scheme].append((idx, int(label), sw_pred, pred, out))

        if step % 1000 == 0:
            elapsed = time.time() - start_time
            print(f'  ... {step}/{n_test} images ({step / elapsed:.0f} img/s)')

    print('\nResults')
    print('-' * 64)
    sw_acc = correct['SW-FLOAT'] / n_test * 100.0
    print(f"{'SW-FLOAT':<14} {correct['SW-FLOAT']:>5}/{n_test:<5} {sw_acc:>8.2f}%")
    for scheme in args.schemes:
        acc = correct[scheme] / n_test * 100.0
        print(f"{scheme_names[scheme]:<14} {correct[scheme]:>5}/{n_test:<5} {acc:>8.2f}%  ({acc - sw_acc:+.2f} vs SW)")

    if args.analysis:
        print('\nConfusion summaries')
        for scheme in args.schemes:
            print(f"\n{scheme_names[scheme]}")
            print(confusion[scheme])
            if mismatches[scheme]:
                print('First mismatches:')
                for idx, label, sw_pred, pred, out in mismatches[scheme]:
                    print(f'  idx={idx} label={label} sw={sw_pred} pred={pred}')


if __name__ == '__main__':
    main()