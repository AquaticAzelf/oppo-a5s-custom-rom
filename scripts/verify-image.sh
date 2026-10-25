#!/bin/sh
# Independent verification of los-custom.img by read-only loop mount.
set -u
C=/mnt/c/Users/Azelf/Documents/zcode
IMG=/root/verify.img
MNT=/mnt/verify
fail=0

cp "$C/build/los-custom-v3.img" "$IMG" || exit 1
mkdir -p "$MNT"
mount -o ro,loop "$IMG" "$MNT" || { echo "MOUNT FAILED"; exit 1; }
cd "$MNT" || exit 1

abs() {
  for p in "$@"; do
    if [ -e "$p" ]; then echo "  STILL PRESENT: $p"; fail=1
    else echo "  gone: $p"; fi
  done
}
pres() {
  for p in "$@"; do
    if [ -e "$p" ]; then echo "  ok: $p"
    else echo "  MISSING: $p"; fail=1; fi
  done
}

echo "--- must be ABSENT (removals + phh-su) ---"
abs product/priv-app/Camera2 product/priv-app/Gallery2 product/app/Jelly \
    product/app/Email product/app/Exchange2 product/app/Recorder \
    app/Terminal app/Traceur app/NfcNci app/PrintSpooler \
    app/BuiltInPrintService app/PrintRecommendationService app/Profiles \
    app/Backgrounds app/EasterEgg app/BasicDreams app/LiveWallpapersPicker \
    app/SecureElement \
    app/treble-overlay-nokia-pnx-8.1-x7-systemui \
    app/treble-overlay-oneplus-op6t-systemui \
    app/treble-overlay-xiaomi-mimix3-systemui \
    app/treble-overlay-xiaomi-redminote6pro-systemui \
    app/treble-overlay-telephony-caf-ims app/treble-overlay-telephony-slsi-ims \
    priv-app/AudioFX priv-app/Updater priv-app/LineageSetupWizard \
    product/app/PhotoTable bin/phh-su etc/init/su.rc

echo "--- must EXIST (keeps + GMS + ports + fixes) ---"
pres phh/secure product/priv-app/SystemUI/SystemUI.apk product/app/LatinIME \
    product/app/Etar product/priv-app/Eleven product/app/messaging \
    priv-app/Seedvault product/priv-app/TrebuchetQuickStep \
    product/app/DeskClock product/app/webview app/Stk \
    product/priv-app/Phonesky/Phonesky.apk \
    product/priv-app/PrebuiltGmsCore/PrebuiltGmsCore.apk \
    product/priv-app/GoogleServicesFramework/GoogleServicesFramework.apk \
    product/priv-app/ConfigUpdater/ConfigUpdater.apk \
    product/priv-app/SetupWizardPrebuilt/SetupWizardPrebuilt.apk \
    product/priv-app/GoogleRestore/GoogleRestore.apk \
    product/priv-app/GoogleExtServices/GoogleExtServices.apk \
    app/GoogleExtShared/GoogleExtShared.apk \
    product/app/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk \
    product/app/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk \
    product/etc/permissions/privapp-permissions-google.xml \
    product/etc/permissions/split-permissions-google.xml \
    product/etc/sysconfig/google.xml \
    product/framework/com.google.android.dialer.support.jar \
    product/framework/com.google.android.maps.jar \
    etc/permissions/bitgapps-permissions-q.xml \
    etc/preferred-apps/google.xml \
    etc/default-permissions/default-permissions-google.xml \
    etc/security/fsverity/play_store_fsi_cert.der \
    etc/security/cacerts/1b0f7e5c.0 etc/security/cacerts/8bec8a00.0 \
    lib64/vendor.oppo.hardware.ktv@1.0.so \
    lib64/vendor.oppo.hardware.biometrics.face@1.0.so \
    lib64/vendor.oppo.hardware.biometrics.fingerprintpay@1.0.so \
    lib64/vendor.oppo.hardware.cryptoeng@1.0.so \
    app/treble-overlay-telephony-mtk-ims product/priv-app/Settings \
    etc/init/98-permissive.rc

echo "98-permissive.rc label: $(getfattr --only-values -n security.selinux etc/init/98-permissive.rc 2>/dev/null)"
echo "98-permissive.rc content: $(cat etc/init/98-permissive.rc | tr '\n' '|')"

echo "cert count: $(ls etc/security/cacerts | wc -l)  (expect 140)"
echo "--- md5 spot checks (image vs source) ---"
md5sum lib64/vendor.oppo.hardware.ktv@1.0.so etc/security/cacerts/1b0f7e5c.0 \
       etc/security/cacerts/8bec8a00.0 \
       "$C/work/trees/stock_system/lib64/vendor.oppo.hardware.ktv@1.0.so"
echo "(certs must be c41430e4... and fe356ea9...)"

cd /
umount "$MNT"
rm -f "$IMG"
if [ "$fail" = 0 ]; then echo "VERIFY RESULT: ALL-OK"; else echo "VERIFY RESULT: PROBLEMS FOUND"; fi
