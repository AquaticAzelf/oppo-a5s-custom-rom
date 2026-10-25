# Changelog

## v7 (2026-10-25) — first public release
- LineageOS 17.1 GSI base + BiTGApps Core (GMS + Play only)
- xHE-AAC decoder built from AOSP libxaac, OMX registry grafted (vndk-27)
- Vendor: 8 linker stubs — 0 CANNOT LINK, vendor services healthy
- VNDK 26/28+sp trimmed (~360 MB)
- 30+ app debloat + Contacts UI removed (provider kept)
- phh-su / xbin/su / phh-secure removed — Magisk-only root
- Permissive + 1.5 GB zram via 2-line post-fs-data fix (zero modules)
- Persist props: brightness 2047, audio effects off
