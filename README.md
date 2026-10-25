# OPPO A5s Custom ROM — LineageOS 17.1, rebuilt

A debloated, fix-forwarded **LineageOS 17.1 (Android 10)** custom ROM **download**
for the **OPPO A5s (CPH1909)** — also sold as the **OPPO AX5s** — powered by the
MediaTek **MT6765 (Helio P35)**. If you are looking for a stable custom ROM or
GSI replacement for ColorOS on the OPPO A5s / AX5s, this is a complete,
ready-to-flash build with a step-by-step guide. The system image, vendor image,
and Magisk boot image are all in the [Releases](https://github.com/AquaticAzelf/oppo-a5s-custom-rom/releases).

**Supported device**

| Model | Aliases | Chipset |
|---|---|---|
| OPPO A5s | AX5s, CPH1909, oppo6765_18511 | MediaTek MT6765 / Helio P35, PowerVR GE8320 |

The ROM is designed as a **zero-module**
build: everything important is baked into the system and vendor partitions, so
a factory reset costs you ~2 minutes of re-setup, not a re-flash.

> **Read [NOTICE.md](NOTICE.md) before using.** Flashing third-party firmware
> carries real risk. You do this at your own risk. Requires an unlocked bootloader.

---

## What makes this build different

| Area | What was done |
|---|---|
| **Debloat** | 30+ apps removed (gallery, email, browser, recorder, themes, debug tools, foreign-device overlays…) — curated, Contacts UI removed while keeping the Contacts **provider** |
| **GMS** | BiTGApps Core: Google Play Store + GMS core only. No extra Google apps |
| **xHE-AAC audio** | Full xHE-AAC decoder **built from source** (AOSP libxaac, armv7 NEON) grafted into the VNDK-27 OMX registry, **and** (v7.1+) placed in the plain-AAC slot — the stock decoder crashes on Meta's xHE-AAC and players that pick the AAC decoder by name (e.g. Facebook Lite) get silent video |
| **Vendor fixes** | 8 linker stubs added to /vendor — kills the 6 boot-time CANNOT-LINK crash-loops (ktv/soter/fingerprint/face) on this GSI |
| **VNDK trim** | Unused VNDK 26/28 variants removed (~360 MB) — vendor needs only 27 + sp |
| **Boot behavior** | SELinux permissive + 1.5 GB zram swap applied every boot via a 2-line Magisk post-fs-data script |
| **Hygiene** | phh-su removed (Magisk is the only root), phh-securize flag removed, brightness/audio-effect persist props set |
| **Zero modules** | No Magisk modules required. Factory reset = Format Data + 2-minute re-setup |

## What does NOT work (accepted hardware/firmware limits)

- Fingerprint & face unlock (vendor trustlet) — dead on any GSI
- Battery temperature in the OS UI reads 0° (the MTK battery driver only
  exposes the non-standard `batt_temp` sysfs node; healthd never sees it).
  The sensor and all thermal zones work — use any thermal app (DevCheck's
  thermal section shows the real temperatures)
- Vulkan: the stock vendor ships no GPU userspace, so it is not in this
  release — our Android 11 + Vulkan kernel/vendor rebuild (work in
  progress) adds a PowerVR 1.13 stack for this exact device
- Sideloading some Play-Protected apps (e.g. Claude) may refuse login on
  uncertified devices — register your build fingerprint once at
  google.com/android/uncertified (see Troubleshooting)

## What's in the Releases

- `los-custom-v7.1.7z` — the system image (v7.1: Facebook Lite audio fix,
  confirmed on device — unzip and verify against SHA256SUMS)
- `vendor-custom.img` — the fixed vendor image
- `boot-magisk.img` — the Magisk-patched boot image
- `SHA256SUMS.txt` — verify everything before flashing
- `flash scripts` — the same scripts this repo builds with

## Documentation

- **[docs/FLASH-GUIDE.md](docs/FLASH-GUIDE.md)** — the complete, step-by-step
  flash guide: backups, mtkclient, BROM flashing, TWRP, setup, Magisk, the
  boot fix, verification, and troubleshooting. **Start here.**
- [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md) — how the image is produced
  (fully reproducible from a public GSI base + these scripts)
- [NOTICE.md](NOTICE.md) — licenses, credits, and legal notes

## The 3-layer design

```
┌──────────────────────────────────────────────────────┐
│ BOOT (Magisk-patched)   │ survives everything        │
│ SYSTEM (this ROM)       │ survives factory resets    │
│ VENDOR (fixed stubs)    │ survives factory resets    │
├──────────────────────────────────────────────────────┤
│ /data/adb/post-fs-data.d/fix.sh  ← the ONLY external │
│ piece: setenforce 0 + zram. Reapplied in ~2 minutes  │
│ after any factory reset (script included).           │
└──────────────────────────────────────────────────────┘
```

Why the 2-line fix lives in /data: this device's **stock OPPO boot ramdisk**
never executes trigger blocks from `/system/etc/init` (services run, triggers
don't — verified across 4 builds). Magisk's `post-fs-data` stage is the one
mechanism that never fails on this phone, so permissive-SELinux + zram live
there. Everything else is baked.
