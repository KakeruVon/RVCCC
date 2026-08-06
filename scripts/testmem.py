import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from torchvision import datasets, transforms


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MEM_DIR = PROJECT_ROOT / "mem_files"
CNN_MEM_PATH = MEM_DIR / "cnn.mem"
CNN_LANE_PATHS = [
    MEM_DIR / f"cnn_b{lane}.mem"
    for lane in range(4)
]
TEST_IMAGE_PATH = MEM_DIR / "test_image.png"


def write_byte_mem(path, values):
    """Write one byte per line in Verilog $readmemh format."""
    with open(path, "w", encoding="ascii") as f:
        for value in values:
            f.write(f"{int(value):02X}\n")


def write_cnn_lane_mem(paths, values):
    """Split the flat 1024-byte image into four byte-lane init files."""
    lanes = [[] for _ in range(4)]

    # Byte address 4*i + lane maps to cnn_b{lane}.mem line i.
    for index, value in enumerate(values):
        lanes[index & 3].append(value)

    for path, lane_values in zip(paths, lanes):
        write_byte_mem(path, lane_values)


def load_test_dataset():
    """Load the MNIST test set with the same 32x32 resize used by training."""
    transform = transforms.Compose([
        transforms.Resize((32, 32)),
        transforms.ToTensor(),
    ])
    return datasets.MNIST(
        root=str(PROJECT_ROOT / "data"),
        train=False,
        download=True,
        transform=transform,
    )


def generate_cnn_mem(img_index=0, mem_path=CNN_MEM_PATH, image_path=TEST_IMAGE_PATH):
    """Generate cnn.mem and test_image.png for one MNIST test image."""
    test_dataset = load_test_dataset()
    if img_index < 0 or img_index >= len(test_dataset):
        raise ValueError(
            f"index {img_index} out of range [0, {len(test_dataset) - 1}]"
        )

    image, label = test_dataset[img_index]
    print(f"Selected image index: {img_index}, label: {label}")

    img_np = (image.numpy() * 255).astype(np.uint8)
    img_flat = img_np.flatten()

    mem_path = Path(mem_path)
    image_path = Path(image_path)
    os.makedirs(mem_path.parent, exist_ok=True)
    write_byte_mem(mem_path, img_flat)

    # The UART flow writes the CNN image at runtime, so the BRAM lane init
    # files are intentionally no longer generated here.
    # write_cnn_lane_mem(CNN_LANE_PATHS, img_flat)

    print(f"Written {len(img_flat)} pixels to {mem_path}")
    # for path in CNN_LANE_PATHS:
    #     print(f"Written {len(img_flat) // 4} bytes to {path}")

    img_save = img_np.squeeze(0)
    pil_img = Image.fromarray(img_save, mode="L")
    os.makedirs(image_path.parent, exist_ok=True)
    pil_img.save(image_path)
    print(f"Saved test image to {image_path}")
    return mem_path, label


def main():
    img_index = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    try:
        generate_cnn_mem(img_index)
    except ValueError as exc:
        print(f"Error: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
