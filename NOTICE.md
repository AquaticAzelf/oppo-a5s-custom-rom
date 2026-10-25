# NOTICE & ATTRIBUTIONS

This project is a **modified Android ROM** for the OPPO A5s (CPH1909). It exists
only because a large body of open-source work makes it possible. All credit for
the foundations belongs to the projects and people below.

## Foundations this build stands on

| Project | Role in this ROM | License |
|---|---|---|
| [AOSP](https://source.android.com/) | Android base | Apache-2.0 |
| [LineageOS 17.1](https://lineageos.org/) | The operating system this ROM modifies | Apache-2.0 (components vary) |
| [phhusson's treble_experimentations](https://github.com/phhusson/treble_experimentations) | The Treble GSI framework that lets a generic system image run on this device | Apache-2.0 |
| [Andy Yan's GSI builds](https://sourceforge.net/projects/andyyan-gsi/) | The specific GSI base image this ROM is derived from | GSI (AOSP-derived) |
| [BiTGApps](https://bitgapps.io/) | The minimal Google-Apps package (GMS + Play Store only) | See upstream |
| [Magisk](https://github.com/topjohnwu/Magisk) | Root solution; Magisk binaries are distributed inside the boot image | **GPL-3.0** — source: https://github.com/topjohnwu/Magisk |
| [libxaac (AOSP)](https://android.googlesource.com/platform/external/libxaac/) | The xHE-AAC decoder source compiled for this ROM | Apache-2.0 |
| MediaTek / OPPO kernel source | Kernel (GPL-2.0). OPPO's GPL release for this device: see `oppo-source/A5S-8.1-kernel-source` on GitHub | GPL-2.0 |
| mtkclient | The flashing tool this project's guides use | GPL-3.0 |
| OPPO vendor binaries | Proprietary blobs from the stock firmware, redistributed for device support only | Proprietary (see disclaimer) |

## Legal disclaimers

1. **No warranty.** This software is provided "AS IS", WITHOUT WARRANTY OF ANY
   KIND. Flashing third-party firmware carries inherent risk, including
   (in worst cases) an unusable device. You flash at your own risk.
2. **Not affiliated.** This project is not affiliated with, endorsed by, or
   supported by OPPO, MediaTek, Google, or the LineageOS project. All product
   names, logos, and brands are property of their respective owners.
3. **Google apps.** The Google Mobile Services components (Play Store, GMS
   Core) included via BiTGApps are Google's proprietary software. Their
   redistribution in custom ROMs is a long-standing community practice, but it
   is not licensed by Google. By using this ROM you accept that responsibility.
4. **Vendor binaries.** The vendor image contains proprietary MediaTek/OPPO
   binaries extracted from the device's own stock firmware, redistributed in
   modified form solely so this specific device functions. They are provided
   for device-support purposes only.
5. **Kernel source.** The Linux kernel in this ROM is GPL-2.0. OPPO has
   published the GPL kernel source for this device; this project does not
   modify the kernel.
6. **Bootloader.** This ROM requires an unlocked bootloader. Unlocking and
   flashing voids your warranty and may trip safety mechanisms.

## What this repository deliberately does NOT contain

- Stock OPPO firmware dumps (preloader, stock boot, stock system/vendor images).
  Always keep your own backup of the stock partitions **before** flashing —
  the flash guide's first phase shows you how.
- Any private keys, tokens, or personal data.
