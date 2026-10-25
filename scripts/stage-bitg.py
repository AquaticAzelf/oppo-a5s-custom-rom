"""Stage BiTGApps Core payload into the final image-relative layout.

Destination map mirrors the working v222 GMS reference image
(product placement) + AOSP standard paths for etc/ files.
Staged tree root == future image root.
"""
import os
import shutil
import tarfile

BASE = r"C:/Users/Azelf/Documents/zcode/work/bitg/tar"
STAGE = r"C:/Users/Azelf/Documents/zcode/build/staged"

# (tarball, dest_dir, keep: None = everything)
CORE = ["ConfigUpdater", "GoogleExtServices", "GoogleRestore",
        "GoogleServicesFramework", "Phonesky", "PrebuiltGmsCore",
        "SetupWizardPrebuilt"]
PERMISSIONS_KEEP = {
    "privapp-permissions-google.xml", "split-permissions-google.xml",
    "variants-permissions-google.xml", "android.ext.services.xml",
    "com.google.android.dialer.framework.xml",
    "com.google.android.dialer.support.xml", "com.google.android.maps.xml",
}

JOBS = []
for name in CORE:
    JOBS.append((f"core/{name}.tar.xz", f"product/priv-app", None))
JOBS += [
    ("etc/GoogleExtShared.tar.xz", "app", None),
    ("etc/GoogleCalendarSyncAdapter.tar.xz", "product/app", None),
    ("etc/GoogleContactsSyncAdapter.tar.xz", "product/app", None),
    ("framework/Framework.tar.xz", "product/framework", None),
    ("Permissions.tar.xz", "product/etc/permissions", PERMISSIONS_KEEP),
    ("Sysconfig.tar.xz", "product/etc/sysconfig", None),
    ("Certificate.tar.xz", "etc/security/fsverity", None),
    ("Preferred.tar.xz", "etc/preferred-apps", None),
    ("Default.tar.xz", "etc/permissions",
     {"bitgapps-permissions-q.xml", "bitgapps-permissions.xml"}),
]

# default-permissions-google.xml goes to its own AOSP standard dir
JOBS_SPECIAL = {"default-permissions-google.xml": "etc/default-permissions"}

if os.path.exists(STAGE):
    shutil.rmtree(STAGE)

count = 0
for rel, dest, keep in JOBS:
    src = os.path.join(BASE, rel.replace("/", os.sep))
    with tarfile.open(src, "r:xz") as t:
        for m in t.getmembers():
            if not m.isfile():
                continue
            base_name = os.path.basename(m.name)
            parent = os.path.dirname(m.name)
            if base_name in JOBS_SPECIAL:
                d = JOBS_SPECIAL[base_name]
            else:
                if keep is not None and base_name not in keep:
                    continue
                # app tarballs carry their own dir: <AppName>/<file>.apk
                d = f"{dest}/{parent}" if parent else dest
            out = os.path.join(STAGE, d.replace("/", os.sep), base_name)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with t.extractfile(m) as fh, open(out, "wb") as o:
                shutil.copyfileobj(fh, o)
            count += 1

print(f"staged {count} files -> {STAGE}")
for root, dirs, files in os.walk(STAGE):
    rel = os.path.relpath(root, STAGE)
    for f in files:
        print(f"  {os.path.join(rel, f)}")
