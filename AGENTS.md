# AGENTS.md — orientation for this repository

Read this before changing anything. It is a map, not a spec. Follow the links for the full picture.

## What this is

LineageOS 17.1 (Android 10) GSI repack for the OPPO A5s / AX5s (CPH1909), MT6765, 3 GB / 32 GB. It starts from an existing GSI. The fixes are baked into `system` and `vendor`, and the scripts here build and flash those images. There is no from-source ROM build. Do not describe it as one.

Images are release assets, never git files. `.gitignore` excludes `*.img`, `*.7z`, `*.gz`, and `*.zip`. A clone gives you no flashable image. Use the [Releases page](https://github.com/AquaticAzelf/oppo-a5s-gsi-repack/releases).

## Which doc answers which question

| Question | Doc |
|---|---|
| How do I flash, back up, or recover? | [docs/FLASH-GUIDE.md](docs/FLASH-GUIDE.md) |
| How are the images built? | [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md) |
| Why these properties and not others? | [docs/PERFORMANCE.md](docs/PERFORMANCE.md) |
| What happened with the custom kernel? | [docs/KERNEL.md](docs/KERNEL.md) |
| Why was some idea abandoned? | [docs/HISTORY.md](docs/HISTORY.md), entries marked `[wrong]` included |
| What works, what is current, what is accepted? | [README.md](README.md) |
| Licenses and attribution? | [NOTICE.md](NOTICE.md) |

## Hard rules

Do not "fix" these without new on-device evidence. Each one cost real time to learn.

- `ro.iorapd.enable` stays `false`. Enabled, it crash-loops: `init` fails `setgid` to gid 1071 and the service dies by signal 6 every five seconds. See `docs/PERFORMANCE.md` section 3.4.
- Any custom kernel must keep the ext4 `async_discard` patch in `fs/ext4/super.c`. Without it `/data` falls back to a 512 MB tmpfs and Android never boots. The patch is reconstructed in the `docs/KERNEL.md` appendix.
- Zero Magisk modules. `fix.sh` and `perf-tune.sh` go into `/data/adb/post-fs-data.d` via `install-fix.bat`. Everything else is baked into the images.
- Do not create the `phh/secure` flag. It makes phh-securize force SELinux back to Enforcing after our permissive rc. `phh-su` is removed and Magisk is the only root.
- Flash order is `system`, then `vendor`, then `boot`, one partition per BROM session via mtkclient. Never write `preloader`, `boot1`, `boot2`, `nvram`, `nvdata`, `seccfg`, `lk`, `lk2`, `md1img`, or `tee1`/`tee2`.
- The published system image is exactly 1,900,544,000 bytes. `build-image.sh` and `verify-image.sh` gate on `EXPECTED_SYSTEM_SIZE`. If image content or size changes, update that gate, `release/SHA256SUMS.txt`, the README download table, and the release notes together.
- v8.0 ships system only. Vendor and boot are unchanged from v7.1 and are not duplicated into newer releases.
- Fingerprint and face unlock, Vulkan, the battery temperature reading, and the parked custom kernel are accepted limits. Do not reopen them. Do not re-test anything in the "What has been eliminated" section of `docs/KERNEL.md`.

## Build order

```
GSI .img.xz -> unsparse.py -> raw ext4 -> resize2fs -> mount
  stage-bitg.py        stage BiTGApps Core
  build-image.sh       debloat, linker stubs, VNDK trim, permissive rc,
                       zram, xAAC OMX graft, OPPO glue libs
  build-opt-system.sh  bake the v8.0 properties, verify inside the mount
  verify-image.sh, verify-vendor.sh, verify-v7-labels.sh   gates
```

`build-xaac-omx.sh` is the shipped decoder path: OMX/vndk-27, 32-bit, baked into the images. `build-xaac.sh` and `xaac-package.py` are marked LEGACY and build a Codec2 APEX Magisk module that does not ship. The boot image is stock boot patched by the Magisk app, with no kernel or ramdisk changes.

## Script map

| Script | Job |
|---|---|
| `scripts/fix.sh` | Permissive SELinux, zram, audio-effects prop |
| `scripts/perf-tune.sh` | Tier-A runtime I/O, VM, stune, and CFS settings |
| `scripts/install-fix.bat` | Deploys both scripts to `/data/adb/post-fs-data.d` |
| `scripts/flash-one.sh` | Writes one partition with allow-list, checksum, and size guards |
| `scripts/build-vendor.sh` | Adds linker stubs and codec XML to your own stock vendor backup |
| `scripts/boot-repack.py` | Unpacks and repacks boot images, swapping only the kernel payload |
| `scripts/read-ext4-file.py` | Reads a live file out of a raw ext4 image without e2fsprogs |
| `scripts/patch-ext4-bytes.py` | Same-length in-place edit inside an ext4 file |
| `scripts/verify-*.sh` | Post-build gates, run before shipping an image |

## Changing anything

1. Run `python -m unittest discover -s tests` before you start and again when you finish. The suite is `tests/test_repo_fixes.py`.
2. Add a test for the behavior you change and watch it fail before you write the fix.
3. Never commit images, archives, credentials, or local build trees. Keep `.gitignore` intact.
4. `.sh` and `.py` files use LF, `.bat` uses CRLF. See `.gitattributes`.
5. The README is the human front door. Keep deep technical detail in `docs/`, and do not paste the kernel or performance essays back into it.
