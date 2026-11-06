#!/usr/bin/env python3
"""patch-ext4-bytes.py — overwrite a byte range inside a file in a raw ext4 image.

In-place, same-length only. Refuses to change the file's size, so no ext4
metadata (inode, extent tree, checksums) is touched.

Used to strip a non-ASCII character out of a build.prop comment without
rebuilding the whole 1.8 GB image.

Usage:
    python patch-ext4-bytes.py <image> <path-in-fs> <find-hex> <replace-hex>
"""
import struct
import sys

MAGIC = 0xEF53


def load_fs(path):
    ns = {}
    src = open(__file__.replace("patch-ext4-bytes.py", "read-ext4-file.py")).read()
    exec(src.split("def main")[0], ns)
    return ns["Ext4"](path), ns


def find_ino(fs, path):
    parts = [p for p in path.split("/") if p]
    ino = 2
    for part in parts:
        d = fs.inode(ino)
        flags, = struct.unpack_from("<I", d, 0x20)
        blocks = fs.extents(d) if flags & 0x80000 else []
        found = None
        for _, pblk, elen in sorted(blocks):
            buf = fs.read_block(pblk, elen)
            off = 0
            while off < len(buf) - 8:
                di, rl, nl, ft = struct.unpack_from("<IHBB", buf, off)
                if rl == 0:
                    break
                name = buf[off + 8: off + 8 + nl].decode("latin-1") if nl else ""
                if name == part:
                    found = di
                    break
                off += rl
            if found:
                break
        if not found:
            raise SystemExit(f"path component not found: {part}")
        ino = found
    return ino


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        return 2
    img, path, find_hex, repl_hex = sys.argv[1:5]
    find = bytes.fromhex(find_hex)
    repl = bytes.fromhex(repl_hex)
    if len(find) != len(repl):
        raise SystemExit("find and replace must be the same length (no resize)")

    fs, _ = load_fs(img)
    bs = fs.block_size
    ino = find_ino(fs, path)
    d = fs.inode(ino)
    size = fs.inode_size_bytes(d)
    flags, = struct.unpack_from("<I", d, 0x20)
    if not (flags & 0x80000):
        raise SystemExit("file is not extent-based; refusing")
    blocks = fs.extents(d)
    content = fs.read_file(d)

    idx = content.find(find)
    if idx < 0:
        raise SystemExit(f"pattern {find_hex} not found in {path}")
    if content.find(find, idx + 1) >= 0:
        raise SystemExit(f"pattern {find_hex} appears more than once; refusing")

    lblk = idx // bs
    off_in = idx % bs
    for lb, pb, ln in sorted(blocks):
        if lb <= lblk < lb + ln:
            phys = pb + (lblk - lb)
            break
    else:
        raise SystemExit("could not map logical block to physical")

    abs_off = phys * bs + off_in
    print(f"file        /{path}  ({size} bytes)")
    print(f"pattern at  file offset {idx}  ->  image offset 0x{abs_off:x}")
    print(f"replace     {find.hex()} -> {repl.hex()}")

    with open(img, "r+b") as f:
        f.seek(abs_off)
        cur = f.read(len(find))
        if cur != find:
            raise SystemExit(f"readback mismatch: found {cur.hex()}, expected {find.hex()}")
        f.seek(abs_off)
        f.write(repl)

    # verify
    fs2, _ = load_fs(img)
    d2 = fs2.inode(find_ino(fs2, path))
    after = fs2.read_file(d2)
    assert len(after) == size, "size changed - abort"
    if find in after:
        raise SystemExit("FAIL: pattern still present after patch")
    if repl not in after:
        raise SystemExit("FAIL: replacement not present after patch")
    print(f"verified    size unchanged ({len(after)} bytes), pattern gone, replacement present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
