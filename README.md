# OPPO A5s Custom ROM — LineageOS 17.1, rebuilt

A debloated, fix-forwarded **LineageOS 17.1 (Android 10)** build for the
**OPPO A5s (CPH1909)** — also sold as the **OPPO AX5s** — on the MediaTek
**MT6765 (Helio P35)**. GSI-based, Magisk-rooted, zero Magisk modules, and
everything that matters baked into the system and vendor partitions.

Images are in [Releases](https://github.com/AquaticAzelf/oppo-a5s-custom-rom/releases).

**Supported device**

| Model | Aliases | Chipset | RAM / storage |
|---|---|---|---|
| OPPO A5s | AX5s, CPH1909, oppo6765_18511 | MediaTek MT6765 / Helio P35, PowerVR GE8320 | 3 GB / 32 GB |

> **Read [NOTICE.md](NOTICE.md) before using.** Flashing third-party firmware
> carries real risk. You do this at your own risk. Requires an unlocked
> bootloader.

---

## Current version — v8.0

| Component | Version | Size | SHA-256 (first 16) |
|---|---|---|---|
| System | **v8.0** | 1,900,544,000 B | `2ca8d883d77b56e6` |
| Vendor | v7.1 (unchanged) | 1,409,286,144 B | `3508b60550a7fe05` |
| Boot | Magisk 30.7 patched | 11,407,360 B | `37fdd90e59e80501` |

Full hashes are in [release/SHA256SUMS.txt](release/SHA256SUMS.txt).
**Verify before flashing.** A truncated image is the single most common cause
of a "bootloop" report.

### What changed in v8.0

v8.0 is a **performance release**, not a feature release. Four properties baked
into the system image, all verified live on device after flashing:

| Property | Value | Why |
|---|---|---|
| `ro.surface_flinger.max_frame_buffer_acquired_buffers` | `3` | Triple buffering. The single most reliable smoothness win on a weak GPU |
| `ro.lmk.kill_timeout_ms` | `1000` | lmkd waits before killing, so it picks a better victim |
| `debug.sf.nobootanimation` | `1` | Skips the boot animation |
| `ro.iorapd.enable` | `false` | Explicitly off — see below |

**`iorapd` is deliberately disabled.** It was tried enabled in the first v8.0
build and crash-looped forever: `init` fails `setgid` to gid 1071 on this
kernel, and the service is killed by signal 6 every 5 seconds. The binary is
fine; it's a platform-level privilege refusal. Pinning the property to `false`
is what stops it. Do not set it back to `true`.

Everything in v7.1 is included unchanged.

---

## What makes this build different

| Area | What was done |
|---|---|
| **Debloat** | 30+ apps removed (gallery, email, browser, recorder, themes, debug tools, foreign-device overlays…) — curated; Contacts UI removed while keeping the Contacts **provider** |
| **GMS** | BiTGApps Core: Play Store + GMS core only. No extra Google apps |
| **xHE-AAC audio** | Full decoder **built from source** (AOSP libxaac, armv7 NEON) grafted into the VNDK-27 OMX registry — **and** placed in the plain-AAC slot, because Meta's HeroPlayer selects the plain AAC decoder by mime and never falls back |
| **Vendor fixes** | 8 linker stubs added to `/vendor` — kills the boot-time `CANNOT LINK` crash-loops (ktv / soter / fingerprint / face) on this GSI |
| **VNDK trim** | Unused VNDK 26/28 variants removed (~360 MB) — this vendor needs only 27 |
| **Boot behaviour** | SELinux permissive + 1.5 GB zram swap applied every boot via a small Magisk `post-fs-data` script |
| **Hygiene** | phh-su removed (Magisk is the only root), `phh/secure` flag removed, brightness / audio-effect persist props set |
| **Zero modules** | No Magisk modules required. A factory reset costs ~2 minutes of setup, not a re-flash |

## What does NOT work (accepted limits — read this before asking)

- **Fingerprint and face unlock** — the vendor trustlet does not work on any
  GSI for this device. Dead, not fixable at this layer.
- **Vulkan** — **not present and not addable.** The device has the PowerVR
  kernel driver (`pvrsrvkm`, compiled in) and DDK 1.9 userspace, but **no
  Vulkan ICD**: no `vulkan.*.so`, no `/vendor/etc/vulkan/`, no feature XML.
  The untouched stock OPPO vendor image contains zero `libvulkan` strings, so
  it was never shipped. `/system/lib64/libvulkan.so` is only the AOSP loader
  and is inert without a driver. There is no kernel change that can fix this.
- **Battery temperature reads 0° in most apps** — the MTK battery driver only
  exposes the non-standard `batt_temp` sysfs node, which healthd never reads.
  The sensor works; use a thermal app (e.g. DevCheck) to see `mtktsbattery`.
- **Some Play-Protected apps refuse login** ("not from Play Store") — Play
  Integrity on an uncertified GSI fingerprint. Register your fingerprint once
  at <https://www.google.com/android/uncertified/> (see Troubleshooting).
- **Custom kernel** — built, boots, but the display runs at ~1 FPS. Not
  shipped. The full story, including why it is parked, is in
  [docs/KERNEL.md](docs/KERNEL.md).

## Performance — where this actually stands

Honest summary, because the internet is full of numbers that do not survive
measurement:

- The panel supports **exactly one mode: 720×1520 @ 59.97 Hz**. There is no
  higher refresh mode to unlock. The stock kernel already reaches the ceiling,
  so no kernel or overclock can raise FPS — only reduce dropped frames.
- The real bottlenecks on this device are **eMMC latency and memory
  bandwidth**, not the CPU scheduler.
- **Overclocking is not worth it.** CPU +8.7 % / +5.6 % and GPU +7.4 % are peak
  figures that thermal throttling takes back within minutes, on a 12 nm fanless
  part. GPU power scales ~1.6× steeper than clock. The project's own verdict is
  "likely net negative".
- What *is* worth it — triple buffering, an I/O scheduler that isn't CFQ,
  `dirty_ratio` that doesn't allow 600 MB of dirty pages, and a zram-aware
  `swappiness` — is already in this build.

Full reasoning and measurements: [docs/PERFORMANCE.md](docs/PERFORMANCE.md).

## Documentation

| Doc | What's in it |
|---|---|
| **[docs/FLASH-GUIDE.md](docs/FLASH-GUIDE.md)** | Complete step-by-step: backups, mtkclient, BROM flashing, TWRP, Magisk, boot fix, verification, troubleshooting. **Start here.** |
| [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md) | How the images are produced, reproducibly |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Every tuning decision, with measurements and rejected ideas |
| [docs/KERNEL.md](docs/KERNEL.md) | The custom kernel: what was built, the display fault, the evidence, why it's parked |
| [docs/HISTORY.md](docs/HISTORY.md) | Chronology, including dead ends worth not re-walking |
| [docs/CLEANUP-WSL.md](docs/CLEANUP-WSL.md) | Removing the WSL build environment completely |
| [NOTICE.md](NOTICE.md) | Licenses, credits, legal notes |

## The 3-layer design

```
┌──────────────────────────────────────────────────────┐
│ BOOT   (Magisk-patched) │ survives everything        │
│ SYSTEM (this ROM)       │ survives factory resets    │
│ VENDOR (linker stubs)   │ survives factory resets    │
├──────────────────────────────────────────────────────┤
│ /data/adb/post-fs-data.d/fix.sh  ← the ONLY external │
│ piece: setenforce 0 + zram. ~2 minutes to reapply    │
│ after any factory reset (script included).           │
└──────────────────────────────────────────────────────┘
```

Why the fix lives in `/data`: this device's **stock OPPO boot ramdisk never
executes trigger blocks from `/system/etc/init`** — services run, triggers
don't (verified across four builds). Magisk's `post-fs-data` stage is the one
mechanism that never fails here, so permissive-SELinux and zram live there.
Everything else is baked.

## Build it yourself

The system image is reproducible from public inputs — a LineageOS 17.1 GSI
base plus the scripts in this repo. The vendor image requires **your own**
stock vendor backup; we do not and will not distribute OPPO's proprietary
blobs. See [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md).

## Credits

LineageOS, Andy Yan's GSI builds, BiTGApps, Magisk (topjohnwu), mtkclient
(bkerler), AOSP libxaac. See [NOTICE.md](NOTICE.md) for licenses.
