#!/bin/sh
# vendor-custom.img verification
set -u
IMG=/mnt/c/Users/Azelf/Documents/zcode/build/vendor-custom.img
mkdir -p /mnt/vv
mount -o ro,loop "$IMG" /mnt/vv || { echo "MOUNT FAILED"; exit 1; }
cd /mnt/vv || exit 1
fail=0
for f in lib64/vendor.oppo.hardware.ktv@1.0.so \
         lib64/vendor.oppo.hardware.cryptoeng@1.0.so \
         lib64/vendor.oppo.hardware.biometrics.fingerprintpay@1.0.so \
         lib64/vendor.oppo.hardware.biometrics.face@1.0.so \
         lib64/vendor.qti.hardware.soter@1.0.so \
         lib64/android.frameworks.fingerprintservice@1.0.so \
         lib64/vendor.oppo.hardware.biometrics.fingerprint@2.1.so \
         lib/vendor.oppo.hardware.biometrics.face@1.0.so \
         lib/android.frameworks.faceservice@1.0.so \
         etc/media_codecs_google_audio.xml; do
  if [ -e "$f" ]; then echo "ok: $f"; else echo "MISSING: $f"; fail=1; fi
done
echo "xaac xml entry: $(grep -c 'OMX.google.xaac.decoder' etc/media_codecs_google_audio.xml) (want 1)"
echo "label: $(getfattr --only-values -n security.selinux lib64/vendor.oppo.hardware.ktv@1.0.so 2>/dev/null)"
echo "total files: $(find . -type f | wc -l) (stock was 1742, ours should be 1751)"
cd /
umount /mnt/vv
if [ "$fail" = 0 ]; then echo "VENDOR VERIFY: ALL-OK"; else echo "VENDOR VERIFY: PROBLEMS"; fi
