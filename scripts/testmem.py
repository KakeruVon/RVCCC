import sys
import torch
from torchvision import datasets, transforms
import numpy as np
import os
from PIL import Image

# 1. 加载测试集（与训练时相同的预处理）
transform = transforms.Compose([
    transforms.Resize((32, 32)),  # 必须缩放到 32x32
    transforms.ToTensor(),        # 转为 [0,1] 的 tensor
])
test_dataset = datasets.MNIST(root='./data', train=False, download=True, transform=transform)

# 2. 选择一张图片（支持命令行参数指定索引，默认第 0 张）
img_index = int(sys.argv[1]) if len(sys.argv) > 1 else 0
if img_index < 0 or img_index >= len(test_dataset):
    print(f"Error: index {img_index} out of range [0, {len(test_dataset)-1}]")
    sys.exit(1)
image, label = test_dataset[img_index]
print(f"Selected image index: {img_index}, label: {label}")

# 3. 转为 0~255 的 uint8 数组（并确保是行优先存储）
img_np = (image.numpy() * 255).astype(np.uint8)   # shape: (1, 32, 32)
img_flat = img_np.flatten()                       # 共 1024 个像素

# 4. 写入 mem 文件（每行一个十六进制字节）
output_path = './mem_files/cnn.mem'  # 替换原有的 cnn.mem
os.makedirs(os.path.dirname(output_path), exist_ok=True)
with open(output_path, 'w') as f:
    for pixel in img_flat:
        f.write(f'{pixel:02X}\n')    # 两位十六进制，如 '00' ~ 'FF'

print(f"Written {len(img_flat)} pixels to {output_path}")

# 5. 将选择的测试集图片保存为 PNG（便于可视化查看）
img_save = img_np.squeeze(0)  # (32, 32) uint8 灰度图
pil_img = Image.fromarray(img_save, mode='L')
img_output_path = './mem_files/test_image.png'
pil_img.save(img_output_path)
print(f"Saved test image to {img_output_path}")