#!/usr/bin/env python3
"""Automatically find a serial port, send CNN image bytes, and print received bytes.

Install the only third-party dependency with:

    python -m pip install pyserial

Examples:

    python scripts/uart_test.py
    python scripts/uart_test.py --port COM7 --baud 115200
    python scripts/uart_test.py --mem mem_files/cnn.mem
    python scripts/uart_test.py --image-index 64
    python scripts/uart_test.py --image-index 64 65 66
    python scripts/uart_test.py --list
"""

from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path
import sys
import time


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MEM_PATH = PROJECT_ROOT / "mem_files" / "cnn.mem"


def load_pyserial():
    try:
        import serial
        from serial.tools import list_ports
    except ModuleNotFoundError as exc:
        raise SystemExit(
            "pyserial is not installed. Run: python -m pip install pyserial"
        ) from exc
    return serial, list_ports


def load_testmem_generator():
    try:
        from testmem import generate_cnn_mem
    except ModuleNotFoundError as exc:
        missing = exc.name or "a required Python package"
        raise SystemExit(
            f"Cannot import scripts/testmem.py because {missing!r} is missing. "
            "Install the testmem dependencies, for example numpy, pillow, "
            "torch, and torchvision."
        ) from exc
    return generate_cnn_mem


def port_label(info) -> str:
    description = info.description or "Unknown device"
    manufacturer = info.manufacturer or ""
    parts = [description]
    if manufacturer and manufacturer not in description:
        parts.append(manufacturer)
    return " - ".join(parts)


def port_score(info) -> int:
    text = " ".join(
        value or ""
        for value in (
            info.device,
            info.description,
            info.manufacturer,
            info.product,
            info.interface,
        )
    ).lower()
    keywords = (
        "uart",
        "usb",
        "serial",
        "ch340",
        "ch341",
        "cp210",
        "ftdi",
        "silicon labs",
        "jtag",
        "xilinx",
    )
    return sum(keyword in text for keyword in keywords)


def find_ports(list_ports):
    ports = list(list_ports.comports())
    return sorted(ports, key=lambda info: (-port_score(info), info.device))


def print_ports(ports) -> None:
    if not ports:
        print("No serial ports found.")
        return

    print("Available serial ports:")
    for index, info in enumerate(ports, start=1):
        print(f"  {index}. {info.device}: {port_label(info)}")


def choose_port(ports, requested: str | None) -> str:
    if requested:
        return requested
    if not ports:
        raise SystemExit(
            "No serial port found. Connect the board and run the script again."
        )

    selected = ports[0]
    print(f"Automatically selected {selected.device}: {port_label(selected)}")
    if len(ports) > 1:
        print("Use --port to select a different port.")
    return selected.device


def format_ascii(data: bytes) -> str:
    result = []
    for value in data:
        if 0x20 <= value <= 0x7E:
            result.append(chr(value))
        elif value == 0x09:
            result.append(r"\t")
        elif value == 0x0A:
            result.append(r"\n")
        elif value == 0x0D:
            result.append(r"\r")
        else:
            result.append(f"\\x{value:02x}")
    return "".join(result)


def load_mem_bytes(path: Path) -> bytes:
    values: list[int] = []
    try:
        with path.open("r", encoding="utf-8") as mem_file:
            for line_number, line in enumerate(mem_file, start=1):
                line = line.split("//", 1)[0].split("#", 1)[0].strip()
                if not line:
                    continue
                for token in line.replace(",", " ").split():
                    if token.startswith("@"):
                        continue
                    try:
                        value = int(token, 16)
                    except ValueError as exc:
                        raise SystemExit(
                            f"{path} line {line_number}: invalid hex byte {token!r}"
                        ) from exc
                    if not 0 <= value <= 0xFF:
                        raise SystemExit(
                            f"{path} line {line_number}: value {token!r} is not a byte"
                        )
                    values.append(value)
    except OSError as exc:
        raise SystemExit(f"Cannot read mem file {path}: {exc}") from exc

    if not values:
        raise SystemExit(f"{path} does not contain any byte values")
    return bytes(values)


def print_received(data: bytes) -> None:
    timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    hex_text = " ".join(f"{value:02X}" for value in data)
    print(
        f"[{timestamp}] "
        f"HEX: {hex_text:<47} "
        f"ASCII: {format_ascii(data)}",
        flush=True,
    )


def read_available(connection) -> bytes:
    data = connection.read(connection.in_waiting or 1)
    if data:
        print_received(data)
    return data


def read_result_line(connection, timeout: float) -> bytes:
    deadline = time.monotonic() + timeout
    received = bytearray()
    while time.monotonic() < deadline:
        remaining = max(0.0, deadline - time.monotonic())
        original_timeout = connection.timeout
        connection.timeout = min(original_timeout or remaining, remaining, 0.1)
        try:
            data = connection.read(connection.in_waiting or 1)
        finally:
            connection.timeout = original_timeout
        if not data:
            continue
        received.extend(data)
        print_received(data)
        if b"\n" in received:
            break
    return bytes(received)


def send_bytes(connection, data: bytes, delay: float, label: str) -> None:
    print(f"Sending {len(data)} bytes from {label}...")
    for index, value in enumerate(data, start=1):
        written = connection.write(bytes((value,)))
        if written != 1:
            raise SystemExit(f"Serial write failed at byte {index}: wrote {written}")
        if delay > 0:
            time.sleep(delay)
        if connection.in_waiting:
            read_available(connection)
    connection.flush()
    print("Send complete.")


def send_existing_mem(connection, mem_path: Path, tx_delay: float) -> None:
    tx_data = load_mem_bytes(mem_path)
    send_bytes(connection, tx_data, tx_delay, str(mem_path))
    print("Waiting for received data. Press Ctrl+C to stop.")
    while True:
        read_available(connection)


def send_generated_images(
    connection,
    image_indices: list[int],
    mem_path: Path,
    tx_delay: float,
    result_timeout: float,
) -> None:
    generate_cnn_mem = load_testmem_generator()
    for img_index in image_indices:
        try:
            generated_path, label = generate_cnn_mem(img_index, mem_path=mem_path)
        except ValueError as exc:
            raise SystemExit(f"Cannot generate image {img_index}: {exc}") from exc

        tx_data = load_mem_bytes(generated_path)
        label_text = f"{generated_path} (MNIST index {img_index}, label {label})"
        send_bytes(connection, tx_data, tx_delay, label_text)

        result = read_result_line(connection, result_timeout)
        if result:
            print(
                f"Result for index {img_index} label {label}: "
                f"ASCII: {format_ascii(result)}"
            )
        else:
            print(f"No result received for index {img_index} within {result_timeout}s")

    print("Batch send complete. Waiting for any further received data. Press Ctrl+C to stop.")
    while True:
        read_available(connection)


def receive_loop(
    serial,
    port: str,
    baud: int,
    timeout: float,
    mem_path: Path,
    tx_delay: float,
    image_indices: list[int] | None,
    result_timeout: float,
) -> None:
    try:
        with serial.Serial(
            port=port,
            baudrate=baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=timeout,
        ) as connection:
            print(f"Connected to {port} at {baud} baud.")
            if image_indices:
                send_generated_images(
                    connection,
                    image_indices,
                    mem_path,
                    tx_delay,
                    result_timeout,
                )
            else:
                send_existing_mem(connection, mem_path, tx_delay)
    except KeyboardInterrupt:
        print("\nStopped.")
    except serial.SerialException as exc:
        raise SystemExit(f"Serial connection failed: {exc}") from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Find a serial port, send CNN image bytes, and print received bytes."
    )
    parser.add_argument(
        "--port",
        help="serial port to use, for example COM7; auto-detected when omitted",
    )
    parser.add_argument(
        "--baud",
        type=int,
        default=115200,
        help="baud rate, default: 115200",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=1.0,
        help="serial read timeout in seconds, default: 1.0",
    )
    parser.add_argument(
        "--mem",
        type=Path,
        default=DEFAULT_MEM_PATH,
        help=f".mem file to send byte-by-byte, default: {DEFAULT_MEM_PATH}",
    )
    parser.add_argument(
        "--image-index",
        type=int,
        nargs="+",
        help="generate cnn.mem from one or more MNIST test indices before sending",
    )
    parser.add_argument(
        "--result-timeout",
        type=float,
        default=5.0,
        help="seconds to wait for one generated image result, default: 5.0",
    )
    parser.add_argument(
        "--tx-delay",
        type=float,
        default=0.0,
        help="delay between transmitted bytes in seconds, default: 0.0",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        dest="list_only",
        help="list serial ports and exit",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.baud <= 0:
        raise SystemExit("--baud must be positive")
    if args.timeout < 0:
        raise SystemExit("--timeout must be non-negative")
    if args.tx_delay < 0:
        raise SystemExit("--tx-delay must be non-negative")
    if args.result_timeout <= 0:
        raise SystemExit("--result-timeout must be positive")

    serial, list_ports = load_pyserial()
    ports = find_ports(list_ports)

    if args.list_only:
        print_ports(ports)
        return 0

    port = choose_port(ports, args.port)
    receive_loop(
        serial,
        port,
        args.baud,
        args.timeout,
        args.mem,
        args.tx_delay,
        args.image_index,
        args.result_timeout,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
