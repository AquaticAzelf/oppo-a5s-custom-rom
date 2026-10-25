#!/bin/sh
# Build vendor-custom.img: stock OPPO vendor + additive codec/glue files.
# Purely additive: 6 x 64-bit stubs, 2 x 32-bit stubs, 1 x xml. Nothing removed.
set -eu
C=/mnt/c/Users/Azelf/Documents/zcode
WORK=/root/vbuild
MNT=/mnt/vendor
S64=$C/work/trees/stock_system/lib64
S32=$C/work/trees/stock_system/lib

echo "[1/6] workspace"
mkdir -p "$WORK" "$MNT"
rm -f "$WORK/vendor-custom.img"

echo "[2/6] copy stock vendor (1.2 GB)"
cp "$C/CLOUD_BACKUP/vendor_stock.bin" "$WORK/vendor-custom.img"

echo "[3/6] mount rw"
mount -o loop,rw "$WORK/vendor-custom.img" "$MNT"
trap 'cd /; umount "$MNT" 2>/dev/null || true' EXIT
cd "$MNT"

echo "[4/6] additive files"
mkdir -p lib64 lib etc
for f in vendor.oppo.hardware.ktv@1.0.so \
         vendor.oppo.hardware.cryptoeng@1.0.so \
         vendor.oppo.hardware.biometrics.fingerprintpay@1.0.so \
         vendor.oppo.hardware.biometrics.face@1.0.so \
         vendor.qti.hardware.soter@1.0.so \
         android.frameworks.fingerprintservice@1.0.so \
         vendor.oppo.hardware.biometrics.fingerprint@2.1.so; do
  cp "$S64/$f" lib64/
done
for f in vendor.oppo.hardware.biometrics.face@1.0.so \
         android.frameworks.faceservice@1.0.so; do
  cp "$S32/$f" lib/
done
cp "$C/xaac-project/out2/media_codecs_google_audio.xml" etc/media_codecs_google_audio.xml
chown 0:0 lib64/*.so lib/*.so etc/media_codecs_google_audio.xml
chmod 644 lib64/*.so lib/*.so etc/media_codecs_google_audio.xml

echo "[5/6] labels (match vendor neighbors)"
REF=$(getfattr --absolute -n security.selinux --only-values lib64/libmtkcam_cct.so 2>/dev/null || true)
[ -n "$REF" ] || REF=$(getfattr --absolute -n security.selinux --only-values bin/hw/android.hardware.media.omx@1.0-service 2>/dev/null || true)
echo "  neighbor label: $REF"
setfattr -n security.selinux -v "$REF" lib64/*.so lib/*.so 2>/dev/null
ETCREF=$(getfattr --absolute -n security.selinux --only-values etc/vintf 2>/dev/null || echo "u:object_r:vendor_configs_file:s0")
setfattr -n security.selinux -v "$ETCREF" etc/media_codecs_google_audio.xml 2>/dev/null

echo "[6/6] unmount, fsck, export"
sync
cd /
umount "$MNT"
e2fsck -fn "$WORK/vendor-custom.img" > /tmp/vfsck.log 2>&1 || true
tail -3 /tmp/vfsck.log
cp "$WORK/vendor-custom.img" "$C/build/vendor-custom.img"
rm -f "$WORK/vendor-custom.img"
echo "VENDOR BUILD DONE: $(stat -c %s "$C/build/vendor-custom.img") bytes"
