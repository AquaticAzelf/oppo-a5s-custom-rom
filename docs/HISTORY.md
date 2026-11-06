# HISTORY — chronology and dead ends

Chronology only. Current truth is [README.md](../README.md), and the technical
detail lives in [PERFORMANCE.md](PERFORMANCE.md) and [KERNEL.md](KERNEL.md).

Entries marked **[wrong]** record a conclusion that later evidence overturned.
They are kept deliberately, so they are not re-derived by the next person.

---

## 2026-10-25 — v7 published

LineageOS 17.1 GSI base + BiTGApps Core (GMS + Play only). xHE-AAC decoder
built from AOSP libxaac and grafted into the VNDK-27 OMX registry. 8 vendor
linker stubs (0 boot-time `CANNOT LINK`). VNDK 26/28 trimmed (~360 MB). 30+
apps removed. phh-su removed (Magisk-only root). Permissive SELinux + 1.5 GB
zram via a two-line post-fs-data script. Zero Magisk modules.

## 2026-10-26 — v7.1 published

Facebook Lite had no audio. Meta's HeroPlayer selects the plain AAC decoder by
mime and never falls back, and the stock Oreo decoder cannot decode xHE-AAC.
The libxaac decoder now also serves the plain-AAC slot in VNDK-27. Verified on
device.

## 2026-10-28 — runbook

Confirmed TWRP is reachable **only** from a full power-off start, never from a
warm reboot.

## 2026-10-29 — research + safety net

Overclock feasibility study (OPP tables, GPU bins, runtime nodes). Full
5-partition snapshot taken to external storage — 28.2 GB with checksums. This
is the parachute referenced in the flash guide.

## 2026-10-30 — Tier-1 shipped, first kernels

- System and vendor images built, `e2fsck -fn` clean.
- Tier-1 flashed and verified across two BROM sessions: vendor 903 → 814 MB,
  zero `CANNOT LINK`, permissive + zram on every boot, rollback drill passed.
- First custom kernel failed: `wmt_loader` looped on a missing
  `/dev/wmtdetect` because the build config differed from factory by 78 lines,
  so `wmt_drv.ko` failed CRC matching.

## 2026-10-31 — the kernel wall

- A build appeared to boot headless. **[wrong]** "boot_completed=1,
  system_server ran, TEE decryption worked" — disproven when `/data` was found
  never to have mounted. With no `/data` there is no crypto state and no
  framework, so that claim cannot have been true.
- Vendor ships seven module files but only six load; the 33 "missing" exports
  come from `wmt_drv.ko` itself. Our builds' `__kcrctab` was zero-filled
  because the PIE link defers CRCs to `.rela.dyn` addends — every `insmod` saw
  CRC 0.
- Static-link attempt boot-looped with no console. A PIE build with raw CRC
  values written into all 9412 `__kcrctab` entries verified 466/466 against the
  vendor modules — and also boot-looped.
- **[wrong]** "The CRC overrides mask real ABI differences." Disproved: the
  layouts are identical, and the loop turned out to be a display oops.

## 2026-11-02 — facts corrected

Only **six** vendor modules load; `met.ko` is referenced by no rc and was
dropped from every loader list. Magisk 30.7 `magiskd` segfaults on the pidfd
syscall (4.9 has none); the daemon restarts, which is unrelated to boot loops.

## 2026-11-03 — panic recovered from expdb

- A kernel flashed to boot only boot-looped; rolled back in one session.
- "Every app not responding" root-caused: the vendor audio HAL crashed 110× in
  `libeffects.so` because `persist.sys.phh.disable_audio_effects` had been
  overridden to `0` in `/data/property`. Forcing it to `1` fixed it; `fix.sh`
  now sets it every boot.
- Slow boots (3.5–6 min) explained: AudioService blocks until audioserver
  registers `media.audio_policy`; Watchdog kills system_server at ~60 s and
  retries.
- **[wrong]** "The build died pre-logger, no trace exists." Corrected the same
  evening: procfs sizes read as 0 in `ls -l`, and MTK ipanic had written the
  panic to **expdb** all along.
- expdb decoded: the kernel oopsed at uptime 0.769 s in `ovl_config_l` (NULL
  deref) after three DDP asserts with `w=-128, h=128`.

## 2026-11-04 — the wall

`/data` never mounted — it fell back to a 512 MB tmpfs, so no crypto state, no
zygote, no framework. Two weeks of builds failed on this one fact.

**[wrong]** "The hang-detect build is the only route left" —
`CONFIG_MTK_AEE_POWERKEY_HANG_DETECT` has no consumer in the tree, and both
hang paths require `system_server`, which never started.

## 2026-11-05 — the wall comes down

- **Root cause: `async_discard`.** `/vendor/etc/fstab.mt6765` asks for it on
  `/data`, `/cache` and `/nvdata`. This kernel's ext4 had only
  `discard`/`nodiscard`, and an unknown option makes `ext4_fill_super()` fail →
  `mount()` returns `EINVAL` → `fs_mgr` gives up → tmpfs. Stock OPPO's kernel
  has the option; a rebuilt mainline-derived tree does not.
- Patched `fs/ext4/super.c` to accept the token. **First custom kernel ever to
  boot Android on this device.**
- IRQ storm fixed (30,000/s → 63/s) and boot time 310 s → 74 s.
- Display still ~1 FPS. Every measurable parameter matches stock. Full
  accounting in [KERNEL.md](KERNEL.md).
- Rolled back to stock. Phone healthy.

## 2026-11-06 — v8.0

- Tier-B properties baked into a new system image and flashed.
- First build enabled `iorapd`; it crash-looped every 5 s (`init: setgid
  failed for iorapd: Invalid argument`). Rebuilt with it explicitly `false`.
- Verified on device: three props live, `init.svc.iorapd=stopped`, zero
  `setgid failed` lines in dmesg.
- Repartitioning evaluated and **rejected**. `system` is 4.20 GiB with 1.77 GiB
  used and `vendor` 1.31 GiB with 1.03 GiB — about 2.5 GiB realistically
  reclaimable. But ext4 block numbers are relative to the partition start, so
  giving that space to `userdata` requires moving its start LBA, which is a
  guaranteed full `/data` wipe, plus hand-editing the GPT on a device whose
  preloader is the only recovery path. Measured `/data`: 22 GB with 10 GB free.
  Not worth it. A microSD card is the zero-risk answer.
- Project closed. Stock kernel, all optimisations that survived measurement.
