#!/usr/bin/env python3
"""Print the built conformance corpus as the gno source that embeds it.

Reads <out>/*.text.bin and <out>/*.data.bin, writes the conformanceCases
literal on stdout. Everything else in conformance_test.gno is hand written.
"""
import pathlib
import sys


def words(path):
    b = path.read_bytes()
    if len(b) % 4:
        b += bytes(4 - len(b) % 4)
    return [int.from_bytes(b[i:i + 4], "little") for i in range(0, len(b), 4)]


def fmt(ws, indent):
    return "\n".join(
        indent + " ".join("0x%08X," % w for w in ws[i:i + 8])
        for i in range(0, len(ws), 8)
    )


def main():
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "out")
    names = sorted({p.name[: -len(".text.bin")] for p in out.glob("*.text.bin")})
    print("var conformanceCases = []conformanceCase{")
    for n in names:
        text = words(out / (n + ".text.bin"))
        dp = out / (n + ".data.bin")
        data = words(dp) if dp.exists() and dp.stat().st_size else []
        print("\t{")
        print('\t\tname: "%s",' % n)
        print("\t\ttext: []uint32{")
        print(fmt(text, "\t\t\t"))
        print("\t\t},")
        if data:
            print("\t\tdata: []uint32{")
            print(fmt(data, "\t\t\t"))
            print("\t\t},")
        print("\t},")
    print("}")


if __name__ == "__main__":
    main()
