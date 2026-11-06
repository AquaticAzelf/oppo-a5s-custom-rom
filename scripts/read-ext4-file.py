#!/usr/bin/env python3
"""read-ext4-file.py — extract a file's content from a raw ext4 image.

Why this exists: after building a system image we must prove what is actually
inside the LIVE file, not what appears in a raw byte scan. A raw grep cannot
distinguish the live file from (a) deleted blocks that were never zeroed or
(b) a backup copy left on the filesystem.

No e2fsprogs required. Handles 64-bit, extents and indirect blocks.

Usage:
    python read-ext4-file.py <image> <path> [<path> ...]
        path is relative to the filesystem root, e.g. build.prop
"""
import struct
import sys

MAGIC = 0xEF53
EXTENTS_FL = 0x80000


class Ext4:
    def __init__(self, path):
        self.f = open(path, "rb")
        self.f.seek(1024)
        sb = self.f.read(1024)
        magic, = struct.unpack_from("<H", sb, 0x38)
        if magic != MAGIC:
            raise SystemExit(f"not an ext2/3/4 filesystem (magic {magic:#x})")

        self.block_size = 1024 << struct.unpack_from("<I", sb, 0x18)[0]
        self.inodes_count, = struct.unpack_from("<I", sb, 0x00)
        self.inodes_per_group, = struct.unpack_from("<I", sb, 0x28)
        self.first_data_block, = struct.unpack_from("<I", sb, 0x14)
        inode_size, = struct.unpack_from("<H", sb, 0x58)
        self.inode_size = inode_size if inode_size else 128
        self.desc_size, = struct.unpack_from("<H", sb, 0xFE)
        if self.desc_size == 0:
            self.desc_size = 32
        incompat, = struct.unpack_from("<I", sb, 0x60)
        self.is64 = bool(incompat & 0x80)

        # group descriptor table
        if self.block_size == 1024:
            gdt = 2 * self.block_size
        else:
            gdt = self.block_size
        self.gdt_offset = gdt

    def group_desc(self, group):
        """Read the descriptor for one block group.

        Required: the inode table lives in a *different place per group*.
        Reading group 0's table for every inode silently returns garbage that
        still looks like a plausible inode (valid mode, valid size) - which is
        exactly the kind of bug that makes a verifier lie.
        """
        self.f.seek(self.gdt_offset + group * self.desc_size)
        d = self.f.read(self.desc_size)
        table = struct.unpack_from("<I", d, 0x08)[0]
        if self.is64 and len(d) >= 0x2C:
            hi, = struct.unpack_from("<I", d, 0x28)
            table |= hi << 32
        return table

    def read_block(self, blk, count=1):
        self.f.seek(blk * self.block_size)
        return self.f.read(self.block_size * count)

    def inode(self, ino):
        group = (ino - 1) // self.inodes_per_group
        idx = (ino - 1) % self.inodes_per_group
        table = self.group_desc(group)
        off = table * self.block_size + idx * self.inode_size
        self.f.seek(off)
        return self.f.read(self.inode_size)

    def inode_size_bytes(self, ino_data):
        # ext4_inode: i_size_lo at 0x04, i_size_high at 0x6C
        # (0x64 is i_generation - reading it there yields a plausible-looking
        #  but completely wrong size, which is a nasty silent bug)
        lo, = struct.unpack_from("<I", ino_data, 0x04)
        hi = 0
        if len(ino_data) >= 0x70:
            hi, = struct.unpack_from("<I", ino_data, 0x6C)
        return lo | (hi << 32)

    def extents(self, ino_data, depth=0, node=None):
        """Return [(logical_block, physical_block, length), ...]."""
        if node is None:
            node = ino_data[0x28:0x28 + 60]
        magic, entries, emax, d = struct.unpack_from("<HHHH", node, 0)
        if magic != 0xF30A:
            return []
        out = []
        for i in range(entries):
            o = 12 + i * 12
            if d == 0:
                lblk, elen, shi, slo = struct.unpack_from("<IHHI", node, o)
                if elen > 32768:      # uninitialised extent
                    elen -= 32768
                out.append((lblk, (shi << 32) | slo, elen))
            else:
                lblk, leaf_lo, leaf_hi = struct.unpack_from("<IIH", node, o)
                blk = (leaf_hi << 32) | leaf_lo
                out.extend(self.extents(ino_data, depth + 1, self.read_block(blk)))
        return out

    def read_file(self, ino_data):
        size = self.inode_size_bytes(ino_data)
        if size == 0:
            return b""
        flags, = struct.unpack_from("<I", ino_data, 0x20)
        data = bytearray()
        if flags & EXTENTS_FL:
            for lblk, pblk, elen in sorted(self.extents(ino_data)):
                data.extend(self.read_block(pblk, elen))
        else:
            # classic direct/indirect blocks
            ptrs = struct.unpack_from("<15I", ino_data, 0x28)
            for p in ptrs[:12]:
                if p:
                    data.extend(self.read_block(p))
            for p in ptrs[12:]:
                if p:
                    for q in struct.unpack("<%dI" % (self.block_size // 4),
                                           self.read_block(p)):
                        if q:
                            data.extend(self.read_block(q))
        return bytes(data[:size])

    def lookup(self, path):
        parts = [p for p in path.split("/") if p]
        ino = 2  # root
        for part in parts:
            ino_data = self.inode(ino)
            size = self.inode_size_bytes(ino_data)
            flags, = struct.unpack_from("<I", ino_data, 0x20)
            if flags & EXTENTS_FL:
                blocks = self.extents(ino_data)
            else:
                ptrs = struct.unpack_from("<15I", ino_data, 0x28)
                blocks = [(i, p, 1) for i, p in enumerate(ptrs[:12]) if p]
            found = None
            for _, pblk, elen in sorted(blocks):
                buf = self.read_block(pblk, elen)
                off = 0
                while off < len(buf):
                    if off + 8 > len(buf):
                        break
                    d_ino, rec_len, name_len, ftype = struct.unpack_from("<IHBB", buf, off)
                    if rec_len == 0:
                        break
                    name = buf[off + 8: off + 8 + name_len]
                    if name_len and name.decode("latin-1") == part:
                        found = d_ino
                        break
                    off += rec_len
                if found:
                    break
            if not found:
                return None
            ino = found
        return self.read_file(self.inode(ino))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    img, paths = sys.argv[1], sys.argv[2:]
    fs = Ext4(img)
    print(f"image        {img}")
    print(f"block size   {fs.block_size}")
    print(f"inode size   {fs.inode_size}")
    print(f"64-bit       {fs.is64}")
    print()
    for p in paths:
        print(f"===== /{p} =====")
        data = fs.lookup(p)
        if data is None:
            print("  NOT FOUND")
        else:
            print(f"  {len(data)} bytes")
            for line in data.decode("latin-1").splitlines():
                print("  " + line)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
