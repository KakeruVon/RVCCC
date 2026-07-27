import os
import sys

import numpy as np
from PIL import Image
from torchvision import datasets, transforms


MEM_DIR = "./mem_files"
CNN_MEM_PATH = os.path.join(MEM_DIR, "cnn.mem")
CNN_LANE_PATHS = [
    os.path.join(MEM_DIR, f"cnn_b{lane}.mem")
    for lane in range(4)
]
TEST_IMAGE_PATH = os.path.join(MEM_DIR, "test_image.png")


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


def main():
    # Step 1: Load the MNIST test set with the same 32x32 resize used by training.
    transform = transforms.Compose([
        transforms.Resize((32, 32)),
        transforms.ToTensor(),
    ])
    test_dataset = datasets.MNIST(
        root="./data",
        train=False,
        download=True,
        transform=transform,
    )

    # Step 2: Pick the image index from the command line, defaulting to image 0.
    img_index = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    if img_index < 0 or img_index >= len(test_dataset):
        print(f"Error: index {img_index} out of range [0, {len(test_dataset) - 1}]")
        sys.exit(1)

    image, label = test_dataset[img_index]
    print(f"Selected image index: {img_index}, label: {label}")

    # Step 3: Convert the tensor from [0, 1] floats to row-major uint8 pixels.
    img_np = (image.numpy() * 255).astype(np.uint8)
    img_flat = img_np.flatten()

    # Step 4: Write the original byte stream and the four BRAM byte-lane files.
    os.makedirs(MEM_DIR, exist_ok=True)
    write_byte_mem(CNN_MEM_PATH, img_flat)
    write_cnn_lane_mem(CNN_LANE_PATHS, img_flat)

    print(f"Written {len(img_flat)} pixels to {CNN_MEM_PATH}")
    for path in CNN_LANE_PATHS:
        print(f"Written {len(img_flat) // 4} bytes to {path}")

    # Step 5: Save the selected 32x32 grayscale image for quick visual inspection.
    img_save = img_np.squeeze(0)
    pil_img = Image.fromarray(img_save, mode="L")
    pil_img.save(TEST_IMAGE_PATH)
    print(f"Saved test image to {TEST_IMAGE_PATH}")


if __name__ == "__main__":
    main()
