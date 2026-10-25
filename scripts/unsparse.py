"""Android sparse image -> raw image converter (simg2img equivalent).

Chunk types per Android sparse format:
  0xCAC1 RAW, 0xCAC2 FILL, 0xCAC3 DONT_CARE, 0xCAC4 CRC32
Usage: python unsparse.py <sparse.img> <raw.img>
"""
import struct
import sys

SPARSE_MAGIC = 0xED26FF3A
RAW, FILL, DONT_CARE, CRC32 = 0xCAC1, 0xCAC2, 0xCAC3, 0xCAC4


def unsparse(src, dst):
    with open(src, "rb") as f:
        hdr = f.read(28)
        if len(hdr) != 28:
            sys.exit("short file")
        (magic, major, minor, file_hdr_sz, chunk_hdr_sz, blk_sz,
         total_blks, total_chunks, checksum) = struct.unpack("<IHHHHIIII", hdr)
        if magic != SPARSE_MAGIC:
            sys.exit(f"not sparse (magic {magic:#x}) - maybe already raw?")
        if file_hdr_sz > 28:
            f.read(file_hdr_sz - 28)
        # chunk headers: 12-byte (v1.0: type,sz,total) or 16-byte (type,r1,r2,sz,total)
        if chunk_hdr_sz not in (12, 16):
            sys.exit(f"unsupported chunk_hdr_sz {chunk_hdr_sz}")
        print(f"{src}: blk={blk_sz} blks={total_blks} "
              f"({total_blks * blk_sz:,} bytes) chunks={total_chunks} "
              f"chunk_hdr={chunk_hdr_sz}")
        written = 0
        counts = {}
        with open(dst, "wb") as out:
            for i in range(total_chunks):
                ch = f.read(chunk_hdr_sz)
                ctype = struct.unpack("<I", ch[:4])[0]
                chunk_blks, total_sz = struct.unpack("<II", ch[-8:])
                data_len = total_sz - chunk_hdr_sz
                nbytes = chunk_blks * blk_sz
                if ctype == RAW:
                    if data_len != nbytes:
                        sys.exit(f"chunk {i}: raw data_len {data_len} != {nbytes}")
                    left = data_len
                    while left:
                        buf = f.read(min(1 << 20, left))
                        if not buf:
                            sys.exit("truncated raw chunk")
                        out.write(buf)
                        left -= len(buf)
                elif ctype == FILL:
                    pat = f.read(4)
                    out.write(pat * (nbytes // 4))
                elif ctype == DONT_CARE:
                    out.write(b"\x00" * nbytes)
                elif ctype == CRC32:
                    f.read(data_len)
                else:
                    sys.exit(f"chunk {i}: unknown type {ctype:#x}")
                counts[ctype] = counts.get(ctype, 0) + 1
                written += nbytes
        print(f"  chunk types: " + ", ".join(f"{k:#x}x{v}" for k, v in sorted(counts.items())))
        print(f"  -> {dst}: {written:,} bytes")
        if written != total_blks * blk_sz:
            sys.exit(f"size mismatch: wrote {written}, expected {total_blks * blk_sz}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    unsparse(sys.argv[1], sys.argv[2])
