# OPPO A5s GSI repack

LineageOS 17.1 (Android 10) for the **OPPO A5s / AX5s (CPH1909)** on the MediaTek MT6765 (Helio P35), 3 GB / 32 GB. It starts from an existing LineageOS GSI. The work here is the fixes baked into system and vendor, plus the scripts to build and flash them. Magisk-rooted, zero modules, debloated, with working xHE-AAC audio.

Images are in [Releases](https://github.com/AquaticAzelf/oppo-a5s-gsi-repack/releases). Read [NOTICE.md](NOTICE.md) before flashing. You need an unlocked bootloader, and you flash at your own risk.

## Contents

- [Download](#download)
- [Flash it](#flash-it)
- [What this changes](#what-this-changes)
- [What does not work](#what-does-not-work)
- [Performance](#performance)
- [How it is put together](#how-it-is-put-together)
- [Build it yourself](#build-it-yourself)
- [Documentation](#documentation)
- [Credits](#credits)

## Download

| Component | Version | Size | SHA-256 (first 16) | Release |
|---|---|---|---|---|
| System | v8.0 | 1,900,544,000 B | `2ca8d883d77b56e6` | v8.0 |
| Vendor | v7.1, unchanged | 1,409,286,144 B | `3508b60550a7fe05` | v7.1 |
| Boot | Magisk 30.7 patched | 11,407,360 B | `37fdd90e59e80501` | v7.1 |

The v8.0 release ships the system image only. If you already have v7.1 installed, you only need the new system image. Full hashes and verification commands are in [release/SHA256SUMS.txt](release/SHA256SUMS.txt).

Verify before flashing. A truncated download is the most common cause of a reported bootloop. The images are release assets, not git files, so a clone alone will not give you anything to flash.

## Flash it

The complete walkthrough, including how to back up stock first, is [docs/FLASH-GUIDE.md](docs/FLASH-GUIDE.md). The short version:

1. Back up your own `system`, `vendor`, and `boot` from BROM mode. This is your way back to stock.
2. Install mtkclient on Windows. This device has no fastboot; every write happens in BROM with the Volume-Down plug-in dance.
3. Download the three images and check every hash against `SHA256SUMS.txt`.
4. Flash one partition per BROM session, in this order: `system`, `vendor`, `boot`.
5. In TWRP: Format Data, wipe cache and dalvik, reboot to system.
6. After first boot, enable USB debugging and Root debugging, then run `scripts/install-fix.bat`. It installs `fix.sh` and `perf-tune.sh`, which give you permissive SELinux, zram, and the runtime tunings on every boot.

Never write `preloader`, `boot1`, `boot2`, `nvram`, `nvdata`, `seccfg`, `lk`, `lk2`, `md1img`, or `tee1`/`tee2`. Doing so can lose your IMEI or hard-brick the phone.

If a write fails, repeat that partition's command. One partition per session means a failure cannot cascade into the others.

## What this changes

| Area | What was done |
|---|---|
| Apps | 30+ removed, curated. Contacts UI goes, the Contacts provider stays |
| Google | BiTGApps Core only: Play Store and GMS core |
| Audio | xHE-AAC decoder built from AOSP libxaac for armv7 NEON, grafted into the VNDK-27 OMX registry and into the plain-AAC slot, because Meta's HeroPlayer never falls back |
| Vendor | 8 linker stubs remove the boot-time `CANNOT LINK` crash-loops |
| Size | Unused VNDK 26/28 variants removed, about 360 MB |
| Root | phh-su removed, Magisk only, no modules required. A factory reset costs about two minutes of setup, not a reflash |

v8.0 is a performance release. Four properties are baked into the system image and were verified live on device:

| Property | Value | Why |
|---|---|---|
| `ro.surface_flinger.max_frame_buffer_acquired_buffers` | `3` | Triple buffering, the most reliable smoothness win on a weak GPU |
| `ro.lmk.kill_timeout_ms` | `1000` | lmkd waits, so it picks a better victim |
| `debug.sf.nobootanimation` | `1` | Skips the boot animation |
| `ro.iorapd.enable` | `false` | See below |

`iorapd` is deliberately off. Enabling it crash-loops the daemon forever: `init` fails `setgid` to gid 1071 on this kernel and the service dies by signal 6 every five seconds. The binary is fine, this is a platform-level privilege refusal. Do not set the property back to `true`.

## What does not work

- **Fingerprint and face unlock.** The vendor trustlet does not work on any GSI for this device. Dead at this layer.
- **Vulkan.** The kernel has the PowerVR driver and DDK 1.9 userspace, but there is no Vulkan ICD: no `vulkan.*.so`, no `/vendor/etc/vulkan/`, no feature XML. The stock OPPO vendor image contains zero `libvulkan` strings, so it never shipped. `/system/lib64/libvulkan.so` is only the AOSP loader. No kernel change fixes this.
- **Battery temperature reads 0° in most apps.** The MTK driver exposes only the non-standard `batt_temp` node, which healthd never reads. The sensor works; a thermal app such as DevCheck can show `mtktsbattery`.
- **Some Play-protected apps refuse login.** Register your fingerprint once at <https://www.google.com/android/uncertified/>. The flash guide has the exact command to read it.
- **The custom kernel.** It boots Android, but the panel runs at about 1 FPS, so it is not shipped. The evidence and the remaining leads are in [docs/KERNEL.md](docs/KERNEL.md).

## Performance

The panel has one mode, 720×1520 at 59.97 Hz. There is no higher refresh rate to unlock, and the stock kernel already reaches that ceiling. The real limits are eMMC latency and memory bandwidth.

Overclocking is not worth it. CPU +8.7% / +5.6% and GPU +7.4% are peak figures that thermal throttling takes back within minutes on a 12 nm fanless chip, and GPU power scales about 1.6 times steeper than clock. What did help, triple buffering, a deadline I/O scheduler, a lower `dirty_ratio`, and zram-aware `swappiness`, is already in this build.

Every measurement and every rejected idea is in [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

## How it is put together

```
BOOT    Magisk-patched, survives everything
SYSTEM  This ROM, survives factory resets
VENDOR  Linker stubs, survives factory resets
--------------------------------------------------
/data/adb/post-fs-data.d/fix.sh   the only external piece
```

The two scripts in `/data/adb/post-fs-data.d` set permissive SELinux, zram, and the runtime tunings. Everything else is baked into the images. The fix has to live there because this device's stock boot ramdisk never executes trigger blocks from `/system/etc/init`. Services run, triggers do not, and that was confirmed across four builds. Magisk's post-fs-data stage is the one mechanism that never fails here.

## Build it yourself

The system image is reproducible from public inputs: a LineageOS 17.1 GSI base plus the scripts in this repo. The vendor image needs your own stock vendor backup. OPPO's proprietary blobs are not distributed here. See [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md).

The regression suite is `tests/test_repo_fixes.py`. Run `python -m unittest discover -s tests` after changing any script.

## Documentation

| Doc | What's in it |
|---|---|
| **[docs/FLASH-GUIDE.md](docs/FLASH-GUIDE.md)** | Backups, mtkclient, BROM flashing, TWRP, Magisk, the boot fix, verification, troubleshooting. Start here |
| [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md) | How the images are produced, reproducibly |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Every tuning decision, with measurements and rejected ideas |
| [docs/KERNEL.md](docs/KERNEL.md) | The custom kernel, the display fault, the evidence, why it is parked |
| [docs/HISTORY.md](docs/HISTORY.md) | Chronology, including dead ends worth not re-walking |
| [docs/CLEANUP-WSL.md](docs/CLEANUP-WSL.md) | Removing the WSL build environment completely |
| [NOTICE.md](NOTICE.md) | Licenses, credits, legal notes |

## Credits

LineageOS, Andy Yan's GSI builds, BiTGApps, Magisk (topjohnwu), mtkclient (bkerler), AOSP libxaac. Licenses are in [NOTICE.md](NOTICE.md).
