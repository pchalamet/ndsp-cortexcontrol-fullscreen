#!/usr/bin/env python3
"""Add the fullscreen shim dependency to every slice of a Mach-O executable."""

import pathlib
import sys

import lief


DEPENDENCY = "@executable_path/libCortexFullscreen.dylib"


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} INPUT OUTPUT", file=sys.stderr)
        return 2

    source = pathlib.Path(sys.argv[1])
    destination = pathlib.Path(sys.argv[2])
    fat_binary = lief.MachO.parse(source)

    if fat_binary is None:
        print(f"could not parse {source}", file=sys.stderr)
        return 1

    changed = 0
    for binary in fat_binary:
        if binary.find_library(DEPENDENCY) is not None:
            continue
        if binary.add_library(DEPENDENCY) is None:
            print(
                f"could not add dependency to {binary.header.cpu_type}",
                file=sys.stderr,
            )
            return 1
        changed += 1

    fat_binary.write(destination)
    print(f"added {DEPENDENCY} to {changed} architecture(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
