"""Map every file inside BiTGApps tarballs: path, type, mode, uid, links."""
import os
import tarfile

BASE = r"C:/Users/Azelf/Documents/zcode/work/bitg"
OUT = r"C:/Users/Azelf/Documents/zcode/analysis/bitg-map.txt"

lines = []
for root, _dirs, files in os.walk(os.path.join(BASE, "tar")):
    for f in sorted(files):
        if not f.endswith(".tar.xz"):
            continue
        p = os.path.join(root, f)
        lines.append(f"\n### {os.path.relpath(p, BASE)}")
        with tarfile.open(p, "r:xz") as t:
            for m in t.getmembers():
                kind = ("d" if m.isdir() else "l" if m.issym()
                        else "h" if m.islnk() else "f")
                extra = f" -> {m.linkname}" if m.issym() else ""
                lines.append(f"  {kind} {oct(m.mode)} uid={m.uid} {m.name}{extra}")

with open(OUT, "w", newline="\n") as fh:
    fh.write("\n".join(lines))
print(f"{len(lines)} lines -> {OUT}")
