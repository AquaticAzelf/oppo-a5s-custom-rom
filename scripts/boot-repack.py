#!/usr/bin/env python3
"""boot-repack.py — unpack / repack the A5s boot image (ANDROID! v0 header).

Verified against CLOUD_BACKUP/stock_boot_A46.img (no MTK 512B prefix —
image starts directly with ANDROID!).

  python boot-repack.py unpack  <boot.img> <outdir>
  python boot-repack.py repack  <outdir> <new-kernel-image> <out-boot.img>

repack swaps ONLY the kernel payload; ramdisk, cmdline, addrs, page size
are kept from the original header.
"""
import os, struct, sys

def unpack(boot_path, outdir):
    d = open(boot_path, 'rb').read()
    assert d[:8] == b'ANDROID!', 'not an Android boot image'
    hdr = struct.unpack('<10I', d[8:48])
    (ksz, kaddr, rsz, raddr, ssz, saddr, tags, page, dt, sec) = hdr
    name, cmdline = d[48:64], d[64:64+512]
    idbytes = d[64+512:64+512+32]
    print(f'kernel_size={ksz} kernel_addr={kaddr:#x}')
    print(f'ramdisk_size={rsz} ramdisk_addr={raddr:#x}')
    print(f'second_size={ssz} tags_addr={tags:#x} page_size={page}')
    print(f'dt_size={dt} name={name.rstrip(bytes(1)).decode(errors="replace")}')
    print(f'cmdline={cmdline.rstrip(bytes(1)).decode(errors="replace")}')
    os.makedirs(outdir, exist_ok=True)
    def rp(n): return (n + page - 1) // page * page
    off = page
    kern = d[off:off+ksz]
    off += rp(ksz)
    ramd = d[off:off+rsz] if rsz else b''
    off += rp(rsz)
    secd = d[off:off+ssz] if ssz else b''
    off += rp(ssz)
    dtb = d[off:off+dt] if dt else b''
    off += rp(dt) if dt else 0
    tail = d[off:]  # MTK tools append trailing bytes — preserve verbatim
    open(f'{outdir}/kernel.img', 'wb').write(kern)
    open(f'{outdir}/ramdisk.img', 'wb').write(ramd)
    open(f'{outdir}/second.img', 'wb').write(secd)
    open(f'{outdir}/dtb.img', 'wb').write(dtb)
    open(f'{outdir}/tail.img', 'wb').write(tail)
    open(f'{outdir}/header.txt', 'w').write(repr(hdr) + '\n' + repr((name, cmdline, idbytes)))
    print(f'unpacked -> {outdir} (tail {len(tail)} bytes)')

def repack(outdir, kernel_path, out_boot):
    hdr = eval(open(f'{outdir}/header.txt').read().split('\n')[0])
    (_ksz, kaddr, _rsz, raddr, ssz, saddr, tags, page, dt, sec) = hdr
    (name, cmdline, idbytes) = eval(open(f'{outdir}/header.txt').read().split('\n')[1])
    kern = open(kernel_path, 'rb').read()
    ramd = open(f'{outdir}/ramdisk.img', 'rb').read()
    secd = open(f'{outdir}/second.img', 'rb').read()
    dtb  = open(f'{outdir}/dtb.img', 'rb').read()
    def rp(n): return (n + page - 1) // page * page
    out = bytearray()
    out += b'ANDROID!'
    out += struct.pack('<10I', len(kern), kaddr, len(ramd), raddr,
                       len(secd), saddr, tags, page, len(dtb), sec)
    out += name + cmdline + idbytes
    out += bytes(page - len(out))  # pad header to page boundary
    out += kern
    out += bytes(rp(len(kern)) - len(kern))
    out += ramd
    out += bytes(rp(len(ramd)) - len(ramd))
    out += secd
    out += bytes(rp(len(secd)) - len(secd))
    out += dtb
    out += bytes(rp(len(dtb)) - len(dtb))
    tail_p = f'{outdir}/tail.img'
    if os.path.exists(tail_p):
        out += open(tail_p, 'rb').read()
    open(out_boot, 'wb').write(out)
    print(f'wrote {out_boot}: {len(out)} bytes (kernel {len(kern)}, ramdisk {len(ramd)})')

if __name__ == '__main__':
    {'unpack': unpack, 'repack': repack}[sys.argv[1]](*sys.argv[2:])
