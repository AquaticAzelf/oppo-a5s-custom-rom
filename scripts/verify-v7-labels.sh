#!/bin/sh

# Repo root — override with PROJECT_ROOT if the tree lives elsewhere.
ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
set -u
mkdir -p /mnt/v7
mount -o ro,loop $ROOT/build/los-custom-v7.img /mnt/v7 || { echo "MOUNT FAILED"; exit 1; }
cd /mnt/v7 || exit 1
for f in etc/init/98-permissive.rc bin/zram-init.sh etc/init/zram.rc lib/vndk-27/libstagefright_soft_xaacdec.so; do
  if [ -e "$f" ]; then
    echo "ok $f | label=$(getfattr --only-values -n security.selinux "$f" 2>/dev/null)"
  else
    echo "MISSING $f"
  fi
done
cd /
umount /mnt/v7
