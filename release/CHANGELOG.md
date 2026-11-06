# Changelog

## v8.0 (2026-11-06) — performance release, verified on device

No new features. Four properties baked into the system image; everything from
v7.1 is unchanged.

- **Added: triple buffering** —
  `ro.surface_flinger.max_frame_buffer_acquired_buffers=3`. Enables
  `preallocateBuffers()` and triples the RenderEngine buffer cache. The one
  graphics change with a physical reason to work on a weak GPU.
- **Changed: lmkd timeout** — `ro.lmk.kill_timeout_ms` 100 → 1000, so lmkd
  picks a better victim instead of killing the first candidate.
- **Added: `debug.sf.nobootanimation=1`** — skips the boot animation.
- **`ro.iorapd.enable` pinned to `false`.** An earlier v8.0 build enabled it
  and the daemon crash-looped every 5 seconds (`init: setgid failed for
  iorapd: Invalid argument`; killed by signal 6). The binary is fine — this is
  a platform-level privilege refusal on gid 1071, unfixable from `/data`.
  Do not set it back to `true`.
- Verified after flashing: three properties live, `init.svc.iorapd=stopped`,
  zero `setgid failed` lines in dmesg, boot 180 s on a cold image.

## v7.1 (2026-10-26) — bug-fix release, confirmed on device
- **Fixed: Facebook Lite videos had no audio.** Meta's HeroPlayer selects the
  plain AAC decoder by mime and never falls back; the stock Oreo decoder
  can't decode xHE-AAC (mp4a.40.42). The xHE-AAC decoder (libxaac, built from
  source) now also serves the plain-AAC slot in VNDK-27 — one decoder handles
  AAC-LC/HE/xHE under either name. Instagram's path unchanged.
- **Fixed: Play-protected apps (e.g. Claude) refusing login** — the guide now
  documents the google.com/android/uncertified fingerprint registration.
- Battery temperature (0°) documented as an accepted limit — the sensor and
  thermal zones work; use a thermal app (e.g. DevCheck → Thermal).
- Verified on device: Facebook Lite audio, Claude login, Instagram, YouTube.

## v7 (2026-10-25) — first public release
- LineageOS 17.1 GSI base + BiTGApps Core (GMS + Play only)
- xHE-AAC decoder built from AOSP libxaac, OMX registry grafted (vndk-27)
- Vendor: 8 linker stubs — 0 CANNOT LINK, vendor services healthy
- VNDK 26/28+sp trimmed (~360 MB)
- 30+ app debloat + Contacts UI removed (provider kept)
- phh-su / xbin/su / phh-secure removed — Magisk-only root
- Permissive + 1.5 GB zram via 2-line post-fs-data fix (zero modules)
- Persist props: brightness 2047, audio effects off
