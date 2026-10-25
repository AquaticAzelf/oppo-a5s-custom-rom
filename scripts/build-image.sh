#!/bin/sh
# Build los-custom.img (LineageOS 17.1 + BiTGApps Core + owner app set + fixes)
# Runs inside Alpine WSL2 as root. Image is modified on WSL-native fs (fast, safe).
set -eu
C=/mnt/c/Users/Azelf/Documents/zcode
WORK=/root/build
MNT=/mnt/build

label_of() { getfattr --absolute -n security.selinux --only-values "$1" 2>/dev/null || true; }
first_match() { for f in $1; do [ -e "$f" ] && { echo "$f"; return 0; }; done; echo "REF-NOT-FOUND: $1" >&2; exit 1; }

echo "[1/7] workspace"
mkdir -p "$WORK" "$MNT"
rm -f "$WORK/los-custom.img"

echo "[2/7] copy base (2.0 GB) into WSL filesystem"
cp "$C/work/los-raw.img" "$WORK/los-custom.img"

echo "[2b/7] grow filesystem 2G -> 3G (LOS image ships ~full; partition is 4.2G)"
resize2fs "$WORK/los-custom.img" 3G >/dev/null 2>&1
echo "  new size: $(stat -c %s "$WORK/los-custom.img") bytes"

echo "[3/7] mount"
mount -o loop,rw "$WORK/los-custom.img" "$MNT"
trap 'cd /; umount "$MNT" 2>/dev/null || true' EXIT
cd "$MNT"

echo "[4/7] owner-approved app removals"
REMOVE="app/EasterEgg app/BasicDreams app/LiveWallpapersPicker app/Terminal
app/Traceur app/NfcNci app/SecureElement app/PrintSpooler app/BuiltInPrintService
app/PrintRecommendationService app/Profiles app/Backgrounds
app/treble-overlay-nokia-pnx-8.1-x7-systemui app/treble-overlay-oneplus-op6t-systemui
app/treble-overlay-xiaomi-mimix3-systemui
app/treble-overlay-xiaomi-redminote6pro-systemui app/treble-overlay-telephony-caf-ims
app/treble-overlay-telephony-slsi-ims
priv-app/AudioFX priv-app/Updater priv-app/LineageSetupWizard
product/app/Email product/app/Exchange2 product/app/Jelly product/app/Recorder
product/app/PhotoTable
product/priv-app/Gallery2 product/priv-app/Camera2 product/priv-app/Contacts
product/etc/permissions/com.android.contacts.xml xbin/su"
MISS=0
for p in $REMOVE; do
  if [ -e "$p" ]; then rm -rf "$p"; else echo "  MISSING: $p"; MISS=1; fi
done
if [ "$MISS" = 1 ]; then
  echo "FATAL: removal list mismatch - aborting (image discarded)"
  cd /; umount "$MNT"; exit 1
fi

echo "[5/7] strip phh-su (Magisk stays the only root)"
rm -f bin/phh-su etc/init/su.rc xbin/su
# NOTE: do NOT create phh/secure - it triggers phh-securize which force-sets
# SELinux Enforcing AFTER our permissive rc (root-caused 2026-10-25). The su
# binaries are removed directly, so the flag is unnecessary.
:

echo "[5f/7] VNDK trim: remove unused 26/28 variants (active config uses 27 + sp-29 only; 0 refs verified)"
rm -rf lib/vndk-26 lib/vndk-28 lib/vndk-sp-26 lib/vndk-sp-28
rm -rf lib64/vndk-26 lib64/vndk-28 lib64/vndk-sp-26 lib64/vndk-sp-28
rm -f fonts/NotoSerifCJK-Regular.ttc
rm -f bin/gdbserver bin/gdbserver64 bin/strace bin/tcpdump bin/simpleperf

echo "[6/7] additions: BiTGApps Core + certs + OPPO glue"
# neighbor label references (authoritative labels from the image itself)
REF_APPDIR=$(first_match "app/CertInstaller")           && LBL_APPDIR=$(label_of "$REF_APPDIR")
REF_APP=$(first_match "app/CertInstaller/*.apk")        && LBL_APP=$(label_of "$REF_APP")
REF_PADIR=$(first_match "product/app/DeskClock")        && LBL_PADIR=$(label_of "$REF_PADIR")
REF_PAAPK=$(first_match "product/app/DeskClock/*.apk")  && LBL_PAAPK=$(label_of "$REF_PAAPK")
REF_PVDIR=$(first_match "product/priv-app/Settings")    && LBL_PVDIR=$(label_of "$REF_PVDIR")
REF_PVAPK=$(first_match "product/priv-app/Settings/*.apk") && LBL_PVAPK=$(label_of "$REF_PVAPK")
REF_PFW=$(first_match "framework/ext.jar")              && LBL_FWJAR=$(label_of "$REF_PFW")
REF_PPERM=$(first_match "product/etc/permissions/*.xml") && LBL_PXML=$(label_of "$REF_PPERM")
REF_PSYS=$(first_match "product/etc/sysconfig/*.xml")   && LBL_SXML=$(label_of "$REF_PSYS")
REF_PERM=$(first_match "etc/permissions/*.xml")         && LBL_XML=$(label_of "$REF_PERM")
REF_ETC=$(first_match "etc/permissions")                && LBL_ETCDIR=$(label_of "$REF_ETC")
REF_CERT=$(first_match "etc/security/cacerts/*.0")      && LBL_CERT=$(label_of "$REF_CERT")
REF_LIB=$(first_match "lib64/libc++.so")                && LBL_LIB=$(label_of "$REF_LIB")
REF_PHH=$(first_match "phh/*")                          && LBL_PHH=$(label_of "$REF_PHH")

set_lbl() { if [ -n "${2:-}" ]; then setfattr -n security.selinux -v "$2" "$1" 2>/dev/null || echo "  WARN: no label set on $1"; else echo "  WARN: empty label for $1"; fi; }

echo "[5b/7] bake SELinux permissive (shotgun: every boot stage - triggers proved flaky)"
{ echo 'on early-fs'
  echo '    setenforce 0'
  echo 'on post-fs-data'
  echo '    setenforce 0'
  echo 'on late-fs'
  echo '    setenforce 0'
  echo 'on boot'
  echo '    setenforce 0'
  echo 'on property:sys.boot_completed=1'
  echo '    setenforce 0'
} > etc/init/98-permissive.rc
chown 0:0 etc/init/98-permissive.rc
chmod 644 etc/init/98-permissive.rc
set_lbl etc/init/98-permissive.rc "u:object_r:system_file:s0"

echo "[5c/7] bake zram swap (KB recipe: 1536M lz4, no module needed)"
printf '#!/system/bin/sh\n# zram swap setup (1536M lz4) - KB recipe\n[ -e /sys/block/zram0/disksize ] || exit 0\ncat /proc/swaps | grep -q zram0 && exit 0\necho 1 > /sys/block/zram0/reset\necho lz4 > /sys/block/zram0/comp_algorithm\necho 1536M > /sys/block/zram0/disksize\nmkswap /dev/block/zram0\nswapon /dev/block/zram0\n' > bin/zram-init.sh
chown 0:0 bin/zram-init.sh; chmod 755 bin/zram-init.sh
set_lbl bin/zram-init.sh "u:object_r:system_file:s0"
printf 'service zram-init /system/bin/zram-init.sh
    class late_start
    user root
    oneshot
' > etc/init/zram.rc
chown 0:0 etc/init/zram.rc; chmod 644 etc/init/zram.rc
set_lbl etc/init/zram.rc "u:object_r:system_file:s0"

echo "[5d/7] persist props as defaults (brightness + audio effects)"
printf 'persist.sys.qcom-brightness=2047\npersist.sys.phh.disable_audio_effects=1\n' >> build.prop

echo "[5e/7] bake xHE-AAC decoder into vndk-27 (registry + library)"
cp "$C/xaac-project/out2/libstagefright_soft_xaacdec.so" lib/vndk-27/
cp "$C/xaac-project/out2/libstagefright_omx.so" lib/vndk-27/libstagefright_omx.so
chown 0:0 lib/vndk-27/libstagefright_soft_xaacdec.so lib/vndk-27/libstagefright_omx.so
chmod 644 lib/vndk-27/libstagefright_soft_xaacdec.so lib/vndk-27/libstagefright_omx.so
REF_VNDK=$(first_match "lib/vndk-27/libstagefright_omx_utils.so")
LBL_VNDK=$(label_of "$REF_VNDK")
set_lbl lib/vndk-27/libstagefright_soft_xaacdec.so "$LBL_VNDK"
set_lbl lib/vndk-27/libstagefright_omx.so "$LBL_VNDK"

label_pair() { # echo "<fileLabel> <dirLabel>" for a path
  case "$1" in
    product/priv-app/*) echo "$LBL_PVAPK $LBL_PVDIR" ;;
    product/app/*)      echo "$LBL_PAAPK $LBL_PADIR" ;;
    app/*)              echo "$LBL_APP $LBL_APPDIR" ;;
    product/framework/*) echo "$LBL_FWJAR $LBL_FWJAR" ;;
    product/etc/permissions/*) echo "$LBL_PXML $LBL_PXML" ;;
    product/etc/sysconfig/*)   echo "$LBL_SXML $LBL_SXML" ;;
    etc/security/fsverity/*)   echo "$LBL_CERT $LBL_CERT" ;;
    etc/*)              echo "$LBL_XML $LBL_ETCDIR" ;;
    lib64/*)            echo "$LBL_LIB $LBL_LIB" ;;
    *)                  echo "" "" ;;
  esac
}

cp -r "$C/build/staged/." .

ADDED="app/GoogleExtShared
product/app/GoogleCalendarSyncAdapter product/app/GoogleContactsSyncAdapter
product/priv-app/ConfigUpdater product/priv-app/GoogleExtServices
product/priv-app/GoogleRestore product/priv-app/GoogleServicesFramework
product/priv-app/Phonesky product/priv-app/PrebuiltGmsCore
product/priv-app/SetupWizardPrebuilt
product/framework/com.google.android.dialer.support.jar
product/framework/com.google.android.maps.jar
product/etc/permissions/android.ext.services.xml
product/etc/permissions/com.google.android.dialer.framework.xml
product/etc/permissions/com.google.android.dialer.support.xml
product/etc/permissions/com.google.android.maps.xml
product/etc/permissions/privapp-permissions-google.xml
product/etc/permissions/split-permissions-google.xml
product/etc/permissions/variants-permissions-google.xml
product/etc/sysconfig/google.xml product/etc/sysconfig/google_build.xml
product/etc/sysconfig/google_exclusives_enable.xml
product/etc/sysconfig/google-hiddenapi-package-whitelist.xml
product/etc/sysconfig/google-initial-package-stopped-states.xml
product/etc/sysconfig/google-install-constraints-allowlist.xml
product/etc/sysconfig/google-rollback-package-whitelist.xml
product/etc/sysconfig/google-staged-installer-whitelist.xml
etc/permissions/bitgapps-permissions-q.xml etc/permissions/bitgapps-permissions.xml
etc/default-permissions etc/preferred-apps etc/security/fsverity"

for t in $ADDED; do
  [ -e "$t" ] || { echo "FATAL: staged item missing after copy: $t"; cd /; umount "$MNT"; exit 1; }
  if [ -d "$t" ]; then
    find "$t" -type d -exec chmod 755 {} +
    find "$t" -type f -exec chmod 644 {} +
    chown -R 0:0 "$t"
    PL=$(label_pair "$t"); FL=${PL%% *}; DL=${PL##* }
    [ -n "$FL" ] && find "$t" -type d -exec setfattr -n security.selinux -v "$DL" {} + 2>/dev/null || echo "  WARN: dir labels on $t"
    [ -n "$FL" ] && find "$t" -type f -exec setfattr -n security.selinux -v "$FL" {} + 2>/dev/null || echo "  WARN: file labels on $t"
  else
    chown 0:0 "$t"; chmod 644 "$t"
    PL=$(label_pair "$t")
    set_lbl "$t" "${PL%% *}"
  fi
done

# GlobalSign R46 + GCC R46 certs (checksum-verified pull from phone)
cp "$C/build/additions/cacerts/1b0f7e5c.0" "$C/build/additions/cacerts/8bec8a00.0" etc/security/cacerts/
chown 0:0 etc/security/cacerts/1b0f7e5c.0 etc/security/cacerts/8bec8a00.0
chmod 644 etc/security/cacerts/1b0f7e5c.0 etc/security/cacerts/8bec8a00.0
set_lbl etc/security/cacerts/1b0f7e5c.0 "$LBL_CERT"
set_lbl etc/security/cacerts/8bec8a00.0 "$LBL_CERT"

# OPPO vendor-glue interface libs from stock system
for lib in vendor.oppo.hardware.ktv@1.0.so \
           vendor.oppo.hardware.biometrics.face@1.0.so \
           vendor.oppo.hardware.biometrics.fingerprintpay@1.0.so \
           vendor.oppo.hardware.cryptoeng@1.0.so; do
  cp "$C/work/trees/stock_system/lib64/$lib" lib64/
  chown 0:0 "lib64/$lib"; chmod 644 "lib64/$lib"
  set_lbl "lib64/$lib" "$LBL_LIB"
done
# agent-B round 2: remaining crash-loop stubs (soter + fingerprintservice 64-bit,
# 32-bit face service needs 32-bit face + faceservice stubs)
for lib in vendor.qti.hardware.soter@1.0.so            android.frameworks.fingerprintservice@1.0.so; do
  cp "$C/work/trees/stock_system/lib64/$lib" lib64/
  chown 0:0 "lib64/$lib"; chmod 644 "lib64/$lib"
  set_lbl "lib64/$lib" "$LBL_LIB"
done
for lib in vendor.oppo.hardware.biometrics.face@1.0.so            android.frameworks.faceservice@1.0.so; do
  cp "$C/work/trees/stock_system/lib/$lib" lib/
  chown 0:0 "lib/$lib"; chmod 644 "lib/$lib"
  set_lbl "lib/$lib" "$LBL_LIB"
done
set_lbl phh/secure "$LBL_PHH"

echo "[7/7] unmount, fsck, export"
sync
cd /
umount "$MNT"
e2fsck -fn "$WORK/los-custom.img" > /tmp/fsck.log 2>&1 || true
tail -3 /tmp/fsck.log
cp "$WORK/los-custom.img" "$C/build/los-custom-v7.img"
rm -f "$WORK/los-custom.img"
echo "BUILD DONE: $(stat -c %s "$C/build/los-custom-v7.img") bytes"
