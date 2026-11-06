#!/bin/sh
# build-opt-system.sh — bake the v8.0 performance properties into a system image.
#
# Usage (inside WSL/Linux, as root):
#   sh build-opt-system.sh <source-system.img> <output-system.img>
#
# Mounts the source image read-write, edits two files, verifies every value
# INSIDE the mounted filesystem, then unmounts and fsck's the result.
#
# Why verify inside the mount: a raw `grep` of a finished ext4 image cannot
# prove a change. Deleted blocks keep stale copies of the old value, so a
# byte-scan will happily "find" the value you removed. Read the live file.
#
# Nothing is flashed. The script stops at the first failure.

set -eu

SRC="${1:?usage: build-opt-system.sh <source.img> <output.img>}"
OUT="${2:?usage: build-opt-system.sh <source.img> <output.img>}"
WORK="${WORKDIR:-/tmp/optbuild}"
MNT="${MNTDIR:-/mnt/optbuild}"

[ -f "$SRC" ] || { echo "FAIL: $SRC not found"; exit 1; }

echo "=============================================================="
echo " system image — bake v8.0 performance properties"
echo "=============================================================="

echo
echo "--- 1/6 source ---"
ls -l "$SRC"
mkdir -p "$WORK" "$MNT"
rm -f "$WORK/build.img"

echo
echo "--- 2/6 copy ---"
cp "$SRC" "$WORK/build.img"
SRC_SIZE=$(stat -c %s "$SRC")

echo
echo "--- 3/6 mount rw ---"
mount -o loop,rw "$WORK/build.img" "$MNT"
trap 'cd /; umount "$MNT" 2>/dev/null || true' EXIT

echo
echo "--- 4/6 apply properties ---"
cd "$MNT"

BP=build.prop
PD=etc/prop.default
[ -f "$BP" ] || { echo "FAIL: $BP not found at image root"; exit 1; }
[ -f "$PD" ] || { echo "FAIL: $PD not found"; exit 1; }

# 1) Triple buffering. Default is 2. At 3, SurfaceFlinger preallocates buffers
#    and triples the RenderEngine cache — the most reliable smoothness win on a
#    weak GPU, for ~4 MB of RAM.
if grep -q '^ro\.surface_flinger\.max_frame_buffer_acquired_buffers=' "$BP"; then
    sed -i 's/^ro\.surface_flinger\.max_frame_buffer_acquired_buffers=.*/ro.surface_flinger.max_frame_buffer_acquired_buffers=3/' "$BP"
    echo "    updated  max_frame_buffer_acquired_buffers=3"
else
    printf '\n# v8.0 performance (see docs/PERFORMANCE.md)\nro.surface_flinger.max_frame_buffer_acquired_buffers=3\n' >> "$BP"
    echo "    added    max_frame_buffer_acquired_buffers=3"
fi

# 2) lmkd: wait 1 s before killing, so it picks a better victim.
sed -i 's/^ro\.lmk\.kill_timeout_ms=.*/ro.lmk.kill_timeout_ms=1000/' "$BP"
echo "    updated  lmk.kill_timeout_ms=1000"

# 3) Skip the boot animation.
if grep -q '^debug\.sf\.nobootanimation=' "$BP"; then
    sed -i 's/^debug\.sf\.nobootanimation=.*/debug.sf.nobootanimation=1/' "$BP"
else
    printf 'debug.sf.nobootanimation=1\n' >> "$BP"
fi
echo "    set      debug.sf.nobootanimation=1"

# 4) iorapd — FORCED OFF. It cannot start on this kernel: init fails setgid to
#    gid 1071 (EINVAL) and the service is killed by signal 6 every 5 s, forever.
#    The binary is fine; this is a platform-level privilege refusal and cannot
#    be fixed from /data because init parses .rc before Magisk mounts.
#    Setting the property false is what stops the crash loop. Do not re-enable.
sed -i 's/^ro\.iorapd\.enable=.*/ro.iorapd.enable=false/' "$PD"
echo "    updated  iorapd.enable=false (cannot run on this kernel)"

echo
echo "--- 5/6 verify INSIDE the image (gate) ---"
FAIL=0
chk() { # chk <file> <pattern> <label>
    if grep -q "$2" "$1"; then echo "    OK   $3"; else echo "    MISS $3"; FAIL=1; fi
}
chk "$BP" '^ro\.surface_flinger\.max_frame_buffer_acquired_buffers=3$' "max_frame_buffer_acquired_buffers=3"
chk "$BP" '^ro\.lmk\.kill_timeout_ms=1000$'                          "lmk.kill_timeout_ms=1000"
chk "$BP" '^debug\.sf\.nobootanimation=1$'                           "nobootanimation=1"
chk "$PD" '^ro\.iorapd\.enable=false$'                               "iorapd.enable=false"
chk "$BP" '^ro\.build\.version\.release=10$'                         "build.prop still intact"

echo "    -- old values must be absent --"
if grep -q '^ro\.lmk\.kill_timeout_ms=100$' "$BP"; then
    echo "    FAIL old lmk.kill_timeout_ms=100 still present"; FAIL=1
else echo "    OK   no stale lmk.kill_timeout_ms=100"; fi
if grep -q '^ro\.iorapd\.enable=true$' "$PD"; then
    echo "    FAIL stale iorapd.enable=true still present"; FAIL=1
else echo "    OK   no stale iorapd.enable=true"; fi

echo "    -- live values --"
grep -E '^ro\.(surface_flinger|lmk)\.|^debug\.sf\.nobootanimation' "$BP" | sed 's/^/       /'
grep -E '^ro\.iorapd\.enable' "$PD" | sed 's/^/       /'

[ "$FAIL" = 0 ] || { echo "FAIL: a property did not apply — do not flash"; exit 1; }

echo
echo "--- 6/6 unmount, fsck, export ---"
cd /
umount "$MNT"
e2fsck -fn "$WORK/build.img" > /tmp/optsys-fsck.log 2>&1 || true
if grep -qiE 'error|corrupt' /tmp/optsys-fsck.log; then
    echo "FAIL: e2fsck reported problems:"
    head -20 /tmp/optsys-fsck.log
    exit 1
fi
echo "    e2fsck clean"

NEW_SIZE=$(stat -c %s "$WORK/build.img")
[ "$SRC_SIZE" = "$NEW_SIZE" ] || { echo "FAIL: size changed $SRC_SIZE -> $NEW_SIZE"; exit 1; }
echo "    size unchanged: $NEW_SIZE bytes"

cp "$WORK/build.img" "$OUT"

echo
echo "=============================================================="
echo " BUILD OK"
ls -l "$OUT"
sha256sum "$OUT"
echo "=============================================================="
echo " Nothing flashed."
echo "=============================================================="
