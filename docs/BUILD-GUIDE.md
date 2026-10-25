# BUILD GUIDE — how this ROM image is produced

The system image is **fully reproducible** from public inputs. No stock OPPO
dumps are needed for the build itself — only the vendor image requires
binaries from your own device (Phase 0 backups of the flash guide).

## Inputs

| Input | Source |
|---|---|
| LineageOS 17.1 GSI base | Andy Yan's `lineage-17.1 ... arm64_avS` build (SourceForge `andyyan-gsi`) |
| BiTGApps Core (arm64, Android 10) | bitgapps.io |
| libxaac source | AOSP `platform/external/libxaac` (Apache-2.0) |
| Android NDK (r27b) | developer.android.com — builds the xHE-AAC decoder |
| WSL2 (Alpine) + e2fsprogs | image surgery: sparse → ext4 → mount → modify → fsck |
| Your device's own `vendor` backup | from the flash guide's Phase 0 (`mtk.py r vendor`) |

## Pipeline overview

```
GSI .img.xz ──unsparse.py──▶ raw ext4 ──resize2fs 3G──▶ mount
   │
   ├─ scripts/stage-bitg.py      (stage BiTGApps Core into product/, curated)
   ├─ scripts/build-image.sh     (the recipe — see below)
   ├─ e2fsck -f                  (filesystem must be clean)
   └─ repack / copy              → los-custom-v7.img  (+ sha256)
```

## What build-image.sh does, in order

1. Removes 30+ apps (curated debloat list — read the `REMOVE` block).
2. Strips `phh-su`, `xbin/su`, `etc/init/su.rc` (Magisk is the only root) and
   makes sure **no** `phh/secure` flag exists (it force-sets Enforcing).
3. Trims VNDK 26/28 + sp variants (~360 MB — this vendor uses only 27).
4. Bakes the SELinux-permissive "shotgun" rc (5 boot stages) and the zram
   service — **every added file gets an explicit SELinux label** (a missing
   label once caused unlabeled-file chaos — don't skip them).
5. Appends persist props (brightness 2047, audio effects off).
6. Installs the xHE-AAC decoder: `libstagefright_soft_xaacdec.so` + the
   **patched `libstagefright_omx.so`** — the OMX registry binary-patch
   replaces the unused FLAC-encoder slot with an `OMX.google.xaac.decoder`
   component (same-length strings, in-place, layout-safe).
7. Stages BiTGApps (GMS+Play) with permission XMLs and default-permissions.
8. Adds GlobalSign certs + the 8 vendor-glue interface libs from the stock
   system tree (ktv/soter/fingerprint/face service stubs).
9. `e2fsck -f` → export → sha256.

## The xHE-AAC decoder build

`scripts/build-xaac-omx.sh` + `xaac-package.py`: compiles AOSP libxaac
(armv7 + NEON, NDK r27b, era-matched source), links it against the vndk-27
OMX headers, bakes `SimpleSoftOMXComponent` (missing from Oreo-era vndk), and
produces the registry-patched OMX lib. The patch is 3 same-length binary
replacements:

```
OMX.google.flac.encoder  →  OMX.google.xaac.decoder
audio_encoder.flac       →  audio_decoder.aac
flacenc                  →  xaacdec
```

## The vendor image

`scripts/build-vendor.sh` takes **your own** stock vendor backup (never ours —
get it from your Phase 0 backup) and adds, purely additively:

- 6× 64-bit linker stubs (`ktv`, `cryptoeng`, `fingerprintpay`, `face`,
  `soter`, `fingerprintservice`) into `/vendor/lib64`
- 2× 32-bit stubs (`face`, `faceservice`) into `/vendor/lib`
- `etc/media_codecs_google_audio.xml` with the xAAC decoder entry
- everything labeled `u:object_r:vendor_file:s0`, then `e2fsck -f`

The release's `vendor-custom.img` was produced exactly this way.

## Boot image

The release boot image is the stock boot **patched by the Magisk app**
(v30.7). No kernel changes, no ramdisk changes — Magisk only. To reproduce:
patch your own stock boot with any Magisk 30.x app ("Select and Patch a
File"). `scripts/boot-repack.py` exists for advanced boot surgery and is
byte-identical roundtrip-tested against this device's boot format.
