#!/bin/sh
# flash-one.sh — write ONE partition via mtkclient BROM, with guards.
#
# Usage:
#   sh flash-one.sh <image> [partition]      # partition defaults to "system"
#
# Environment:
#   MTKCLIENT=/path/to/mtkclient    where mtk.py lives (default: .)
#   MTK_PYTHON=python3              interpreter to use
#
# Guards, in order:
#   1. a .sha256 sidecar must exist and match  — never flash an unverified file
#   2. a size sanity check                    — a boot image is ~11 MB, a
#      system image is ~1.8 GB; passing the wrong file to the wrong partition
#      is how phones become unbootable
#   3. the partition must be on the allow-list — preloader, nvram, nvdata,
#      seccfg, lk, tee and friends are never writable by this script
#
# It writes exactly one partition and then exits. One partition per BROM
# session is deliberate: a failure mid-session cannot cascade.

set -e

IMG="${1:?usage: flash-one.sh <image> [partition]}"
PART="${2:-system}"
M="${MTKCLIENT:-.}"
PY="${MTK_PYTHON:-python3}"

[ -f "$IMG" ] || { echo "FAIL: $IMG not found"; exit 1; }

# --- guard 1: allow-list ---
case "$PART" in
    system|vendor|boot) : ;;
    *) echo "FAIL: refusing to write partition '$PART'."
       echo "      This script only writes: system, vendor, boot."
       echo "      Writing preloader/nvram/nvdata/seccfg/lk/tee can lose your"
       echo "      IMEI or hard-brick the device."
       exit 1 ;;
esac

# --- guard 2: checksum sidecar ---
SC="$IMG.sha256"
[ -f "$SC" ] || { echo "FAIL: no sidecar $SC — refusing to flash unverified"; exit 1; }
( cd "$(dirname "$IMG")" && sha256sum -c "$(basename "$SC")" ) || {
    echo "FAIL: sha256 mismatch — do not flash"; exit 1; }
echo "=== sha256 OK ==="

# --- guard 3: size sanity ---
SZ=$(stat -c %s "$IMG")
case "$PART" in
    boot)
        if [ "$SZ" -gt 100000000 ]; then
            echo "FAIL: $IMG is $SZ bytes — far too big for a boot partition."
            echo "      That looks like a system or vendor image."
            exit 1
        fi ;;
    system|vendor)
        if [ "$SZ" -lt 500000000 ]; then
            echo "FAIL: $IMG is only $SZ bytes — too small for a $PART image."
            echo "      A boot image is ~11 MB and would be written into $PART."
            exit 1
        fi ;;
esac
echo "=== size OK: $SZ bytes ==="

echo
echo "=== WRITE $PART — waiting for BROM ==="
echo "    phone OFF, hold Vol-Down, plug USB, keep holding ~5 s"
cd "$M"
"$PY" mtk.py w "$PART" "$IMG"

echo
echo "=== $PART WRITE COMPLETE ==="
echo "    unplug, power on. A fresh system image re-runs dex2oat: first boot is slow."
