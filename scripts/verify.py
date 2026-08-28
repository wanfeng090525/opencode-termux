#!/usr/bin/env python3
"""Structural verification for a bun-termux-loader wrapped binary.

Usage:  python3 scripts/verify.py <wrapped-binary> [expected_ver]
Exit 0 = pass, 1 = fail.
Layout expected:
  [Bionic wrapper ELF] [BUNWRAP1 + bun_elf_size] [Bun ELF] [BUNLIBS1] [JS+trailer]
"""
import struct
import subprocess
import sys

MARKER = b"BUNWRAP1"
RAW_LINKER = b"/lib/ld-linux-aarch64.so.1"


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dump = None
    if "--dump-inner" in sys.argv:
        dump = sys.argv[sys.argv.index("--dump-inner") + 1]
    if not args:
        print("usage: python3 scripts/verify.py <wrapped> [expect_bun_size] [--dump-inner OUT]", file=sys.stderr)
        return 2
    path = args[0]
    expect = int(args[1]) if len(args) > 1 and args[1].isdigit() else None

    data = open(path, "rb").read()
    print(f"file={path} size={len(data)}")

    if data[:4] != b"\x7fELF":
        print("FAIL: not an ELF", file=sys.stderr)
        return 1

    # Literal MARKER also appears inside the wrapper's own code; real metadata is LAST occurrence.
    idxs = [i for i in range(len(data)) if data.startswith(MARKER, i)]
    if not idxs:
        print("FAIL: BUNWRAP1 missing", file=sys.stderr)
        return 1
    idx = idxs[-1]
    bun_sz = struct.unpack("<Q", data[idx + 8 : idx + 16])[0]
    print(f"BUNWRAP1 @ {idx}, bun_elf_size={bun_sz}")
    if expect and bun_sz != expect:
        print(f"FAIL: bun_elf_size {bun_sz} != expected {expect}", file=sys.stderr)
        return 1

    bun = data[idx + 16 : idx + 16 + bun_sz]
    if bun[:4] != b"\x7fELF":
        print("FAIL: embedded Bun ELF invalid", file=sys.stderr)
        return 1
    e_machine = struct.unpack_from("<H", bun, 18)[0]
    ok_arch = e_machine == 183
    print(f"embedded ELF aarch64 = {ok_arch}")
    print(f"glibc interpreter referenced = {RAW_LINKER in bun}")

    after = data[idx + 16 + bun_sz :][:8]
    print(f"after Bun ELF magic: {after!r} (BUNLIBS1 expected)")

    tail = data[-4 * 2**20 :]
    print(
        "Bun trailer present =",
        (b"packages by bun" in tail) or (b"---- Bun! ----" in tail),
    )

    final_sz = struct.unpack("<Q", data[-8:])[0]
    ok_size = final_sz == len(data)
    print(f"final_size==file_size = {ok_size}")

    print("file(1):", subprocess.run(["file", "-b", path], capture_output=True, text=True).stdout.strip())

    if dump:
        with open(dump, "wb") as f:
            f.write(bun)
        print(f"dumped inner aarch64 Bun ELF ({len(bun)} bytes) -> {dump}")

    return 0 if (ok_arch and ok_size) else 1


if __name__ == "__main__":
    sys.exit(main())