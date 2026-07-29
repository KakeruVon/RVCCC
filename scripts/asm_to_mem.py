#!/usr/bin/env python3
"""Build a RISC-V assembly file into a Verilog $readmemh instruction image."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


DEFAULT_WORDS = 256
DEFAULT_ARCH = "rv32i"
DEFAULT_ABI = "ilp32"


def find_executable(candidates: list[str]) -> str | None:
    for candidate in candidates:
        if not candidate:
            continue
        found = shutil.which(candidate)
        if found:
            return found
    return None


def derive_objcopy(cc: str | None) -> str | None:
    if not cc:
        return None

    cc_path = Path(cc)
    name = cc_path.name
    suffix = ".exe" if name.endswith(".exe") else ""
    stem = name[:-4] if suffix else name

    for cc_suffix in ("-gcc", "-clang", "gcc", "clang"):
        if stem.endswith(cc_suffix):
            objcopy_name = stem[: -len(cc_suffix)] + "-objcopy" + suffix
            sibling = cc_path.with_name(objcopy_name)
            if sibling.exists():
                return str(sibling)
            found = shutil.which(objcopy_name)
            if found:
                return found

    return None


def resolve_toolchain(args: argparse.Namespace) -> tuple[str, str]:
    cc_candidates = [
        args.cc,
        os.environ.get("RISCV_GCC"),
        os.environ.get("RISCV_CC"),
        "riscv64-unknown-elf-gcc",
        "riscv32-unknown-elf-gcc",
    ]
    cc = find_executable(cc_candidates)
    if not cc:
        raise SystemExit(
            "Could not find a RISC-V GCC executable. Install a RISC-V GNU "
            "toolchain or pass --cc /path/to/riscv*-unknown-elf-gcc."
        )

    objcopy_candidates = [
        args.objcopy,
        os.environ.get("RISCV_OBJCOPY"),
        derive_objcopy(cc),
        "riscv64-unknown-elf-objcopy",
        "riscv32-unknown-elf-objcopy",
    ]
    objcopy = find_executable([candidate for candidate in objcopy_candidates if candidate])
    if not objcopy:
        raise SystemExit(
            "Could not find a RISC-V objcopy executable. Install it or pass "
            "--objcopy /path/to/riscv*-unknown-elf-objcopy."
        )

    return cc, objcopy


def run(cmd: list[str]) -> None:
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.returncode) from exc


def bytes_to_mem(binary: bytes, words: int, pad_word: int) -> tuple[list[str], int]:
    if len(binary) % 4 != 0:
        raise SystemExit(f".text size is {len(binary)} bytes, not a multiple of 4")

    used_words = len(binary) // 4
    if used_words > words:
        raise SystemExit(
            f"Program uses {used_words} words, but instruction memory only has {words} words"
        )

    lines = [
        f"{int.from_bytes(binary[i:i + 4], byteorder='little'):08x}"
        for i in range(0, len(binary), 4)
    ]
    lines.extend([f"{pad_word & 0xffff_ffff:08x}"] * (words - used_words))
    return lines, used_words


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Assemble RV32I code and write mem_files/instruction.mem format."
    )
    parser.add_argument("source", type=Path, help="input .S/.s assembly file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("mem_files/instruction.mem"),
        help="output .mem file, default: mem_files/instruction.mem",
    )
    parser.add_argument(
        "--words",
        type=int,
        default=DEFAULT_WORDS,
        help=f"instruction memory depth in 32-bit words, default: {DEFAULT_WORDS}",
    )
    parser.add_argument("--arch", default=DEFAULT_ARCH, help=f"RISC-V ISA, default: {DEFAULT_ARCH}")
    parser.add_argument("--abi", default=DEFAULT_ABI, help=f"RISC-V ABI, default: {DEFAULT_ABI}")
    parser.add_argument("--cc", help="RISC-V GCC executable")
    parser.add_argument("--objcopy", help="RISC-V objcopy executable")
    parser.add_argument(
        "--pad-word",
        type=lambda text: int(text, 0),
        default=0,
        help="word used to pad unused instruction memory, default: 0",
    )
    parser.add_argument(
        "--keep-build-dir",
        action="store_true",
        help="keep temporary ELF and binary files for debugging",
    )
    args = parser.parse_args()

    if args.words <= 0:
        raise SystemExit("--words must be positive")
    if not args.source.exists():
        raise SystemExit(f"source file does not exist: {args.source}")

    cc, objcopy = resolve_toolchain(args)
    tmp = tempfile.TemporaryDirectory(prefix="rvccc_asm_")
    build_dir = Path(tmp.name)
    try:
        elf = build_dir / "program.elf"
        binary_path = build_dir / "program.bin"

        run(
            [
                cc,
                "-x",
                "assembler-with-cpp",
                f"-march={args.arch}",
                f"-mabi={args.abi}",
                "-nostdlib",
                "-nostartfiles",
                "-Wl,-Ttext=0x0",
                "-Wl,-e,0x0",
                "-Wl,--no-relax",
                "-Wl,--build-id=none",
                "-o",
                str(elf),
                str(args.source),
            ]
        )
        run([objcopy, "-O", "binary", "-j", ".text", str(elf), str(binary_path)])

        lines, used_words = bytes_to_mem(binary_path.read_bytes(), args.words, args.pad_word)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text("\n".join(lines) + "\n", encoding="ascii")

        print(f"Wrote {args.output} ({used_words}/{args.words} instruction words used)")
        if args.keep_build_dir:
            print(f"Kept build directory: {build_dir}")
            tmp = None
    finally:
        if tmp is not None:
            tmp.cleanup()

    return 0


if __name__ == "__main__":
    sys.exit(main())

