# FLASH GUIDE — OPPO A5s Custom ROM (complete, start to finish)

Target device: **OPPO A5s (CPH1909)**, MediaTek MT6765 (Helio P35), 3 GB RAM.
Total time: about 45–60 minutes, most of it waiting.
Skill needed: follow steps exactly. If a step says "wait", wait.

---

## ⚠️ Read this first

- **You need an unlocked bootloader.** If yours is locked, stop — research
  MT6765 unlock methods first (this is a separate, device-specific process).
- **Charge the phone.** Keep it on the charger for the whole procedure.
- Flashes happen over **BROM mode** (the chip's lowest-level boot ROM), using
  [mtkclient](https://github.com/bkerler/mtkclient). No fastboot needed —
  this device has none.
- **Phase 0 (backups) is not optional.** It is your parachute.
- **NEVER flash these partitions:** `preloader`, `boot1`, `boot2`,
  `nvram`, `nvdata`, `seccfg`, `lk`, `lk2`, `md1img`, `tee1/tee2`.
  Writing those can lose your IMEI or hard-brick the phone. This guide
  only ever writes `system`, `vendor`, `boot`.

---

## PHASE 0 — Back up YOUR phone first (your parachute)

Do this even if everything looks fine. It takes 20–30 minutes and gives you a
full restore path to stock.

1. Install mtkclient (Phase 1 below) first — you need it for this.
2. Power the phone **off**, hold **Volume-Down**, plug the USB cable.
3. From the mtkclient folder, read your stock partitions (one per plug-in,
   same "dance" as flashing — the tool waits for BROM each time):

```bat
python mtk.py r system
python mtk.py r vendor
python mtk.py r boot
```

4. Each partition lands in the mtkclient `output` folder as a `.bin` file.
5. **Copy that folder somewhere safe (a second drive).** If you ever want
   stock back, you restore with the same commands, `w` instead of `r`.

You now hold your own escape hatch. Everything after this is reversible.

---

## PHASE 1 — Install mtkclient (Windows)

1. Install [Python 3.9+](https://python.org) (tick "Add to PATH").
2. Download mtkclient: `git clone https://github.com/bkerler/mtkclient`
   (or download the ZIP and extract).
3. In that folder:

```bat
pip3 install -r requirements.txt
```

4. Install the USB filter driver: run `Setup\Readme.txt`'s instructions —
   on Windows this is the `pwrun.bat` / driver-install step in the `Setup`
   folder (accept the unsigned-driver prompt).

Test it: `python mtk.py --help` should print usage.

---

## PHASE 2 — Download this ROM + verify

1. From this repo's **Releases** page, download:
   - `los-custom-v7.7z.001` + `.002` (the system image, split for GitHub's
     2 GB-per-file limit)
   - `vendor-custom.img`
   - `boot-magisk.img`
   - `SHA256SUMS.txt`
2. Rejoin the system image: install [7-Zip](https://7-zip.org), then
   right-click `los-custom-v7.7z.001` → **7-Zip → Extract here**.
   You now have `los-custom-v7.img` (3 GB).
3. Verify everything (PowerShell or cmd, in the download folder):

```bat
certutil -hashfile los-custom-v7.img SHA256
certutil -hashfile vendor-custom.img SHA256
certutil -hashfile boot-magisk.img SHA256
```

Compare against `SHA256SUMS.txt`. **If any hash differs, do not flash.**

---

## PHASE 3–5 — Flash the three partitions (BROM dance)

You will do the same small ritual three times, once per partition.
**The ritual:**

> 1. Phone **powered OFF** completely (screen black, no charging icon).
> 2. **Hold Volume-Down.**
> 3. **Plug the USB cable** while still holding Volume-Down.
> 4. Keep holding ~5 seconds. The screen stays **fully black** — that is
>    correct (that's BROM mode). No logo, no charging animation.
> 5. If you see a logo or anything on screen: you missed it — unplug, hold
>    power 10 s to shut down, and try again. It's normal to need 2–3 tries.

**Flash system** (3 GB — takes ~7 minutes at ~7.5 MB/s):

```bat
python mtk.py w system path\to\los-custom-v7.img
```

Wait for `Wrote ... to sector ...` and 100%. Then **unplug**.

**Flash vendor** (~3 minutes):

```bat
python mtk.py w vendor path\to\vendor-custom.img
```

Unplug.

**Flash boot** (~10 seconds):

```bat
python mtk.py w boot path\to\boot-magisk.img
```

Unplug.

> ⚠️ One partition at a time, one plug-in at a time. If a write is
> interrupted, just run that same command again — nothing else is harmed.

---

## PHASE 6 — Format Data in TWRP

1. Boot TWRP recovery (power off, then your recovery key combo —
   on this device: hold **Volume-Down + Power** until the recovery appears;
   if it boots the ROM instead, power off and retry).
2. TWRP will say it can't decrypt — that's expected.
3. **Wipe → Format Data** → type `yes`. This is the real factory-grade wipe.
4. **Wipe → Advanced Wipe →** tick **cache** and **dalvik** → swipe.
5. **Reboot → System.**

---

## PHASE 7 — First boot + setup

1. LineageOS logo, then a **slow first boot** (3–10 minutes — background
   optimization; the phone may feel hot; that's normal, once).
2. Complete the setup wizard. Google account now or later — your choice.
3. Already baked in: Play Store + GMS, the xHE-AAC decoder, all app removals.
4. If a system-update prompt ever appears: **never accept it.**

---

## PHASE 8 — Developer options

1. **Settings → About phone → tap Build number 7 times.**
2. Back to **System → Developer options**, enable:
   - **USB debugging**
   - **Root debugging**  ← this one matters later
3. Plug the phone into the PC. Accept the debugging prompt on the phone.
4. Test: `adb devices` shows your phone; `adb root` replies
   "restarting adbd as root".

---

## PHASE 9 — Magisk (the step everyone gets wrong)

1. Install the app:
   `adb install path\to\Magisk-v30.7.apk`
2. Open the Magisk app. If it shows **Install → "Direct Install (Recommended)"**,
   run it and **reboot when it asks**.
3. **Critical quirk:** after a Format Data, Magisk's script environment
   (`/data/adb/magisk/`) is empty, and the app merely *opening* it does NOT
   rebuild it — magiskd will log `Magisk environment incomplete, abort` and
   skip every boot script. The app's **Install → Direct Install** flow is
   what rebuilds the environment. Do not skip it.
4. After the reboot, verify: open Magisk — it should say **Installed: 30.7**,
   no warnings.

---

## PHASE 10 — The boot fix (the one external piece)

This 2-line script gives you **SELinux permissive + 1.5 GB zram swap on every
boot** via Magisk's post-fs-data stage. Without it the ROM boots Enforcing
with no swap.

**Easy way:** double-click `scripts\install-fix.bat` (from this repo) with the
phone plugged in and Root debugging on.

**Manual way:**

```bat
adb root
adb shell "mkdir -p /data/adb/post-fs-data.d"
adb push fix.sh /data/adb/post-fs-data.d/fix.sh
adb shell "chmod 755 /data/adb/post-fs-data.d/fix.sh && restorecon /data/adb/post-fs-data.d/fix.sh"
```

Then **reboot**.

> If after reboot things still aren't right, see Troubleshooting below —
> there's a label check that fixes a rare Magisk quirk.

---

## PHASE 11 — Verify

With the phone plugged in and Root debugging on:

```bat
adb shell getenforce                 → want: Permissive
adb shell cat /proc/swaps            → want: a /dev/block/zram0 line (~1.5 GB)
adb shell "strings /system/lib/vndk-27/libstagefright_omx.so | findstr xaac"
                                     → want: OMX.google.xaac.decoder
adb shell "logcat -b all -d | findstr /C:\"CANNOT LINK\""
                                     → want: 0 lines
adb shell "ls /data/adb/modules"     → want: empty (zero-module design)
```

Final seal: **play an Instagram or Facebook reel with the sound on.** The
audio must survive the whole clip — that's the xHE-AAC decoder working.

Done. Install your apps (Open Camera, your launcher, your games) and go.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Phone boots to logo then black / bootloops | Bad or interrupted write | Re-run that partition's flash command (Phase 3–5) |
| `mtk.py` finds no device when plugged | Missed BROM window | Unplug, hold power 10 s, retry the ritual (hold Vol- the whole time). Normal to need 2–3 tries |
| mtkclient hangs and won't die | Zombie process holding USB | **Unplug the cable** — the stuck process loses its handle and dies; kill leftover `python.exe` in Task Manager, restart the command |
| Magisk log: `Magisk environment incomplete` | Environment empty after Format Data | Magisk app → **Install → Direct Install** → reboot (Phase 9) |
| Magisk scripts run but state wrong / labels odd | SELinux label drift on /data/adb | `adb shell "chcon -R u:object_r:adb_data_file:s0 /data/adb"` then reboot |
| `adb root` says "disabled by system setting" | Root debugging toggle flipped off | Settings → Developer options → re-enable Root debugging |
| Instagram/Facebook video silent | Decoder not engaged | Check Phase 11's xaac string test; ensure you flashed the release's system image |
| Facebook Lite video plays but has no sound | HeroPlayer picks the plain AAC decoder by mime and never falls back; the stock Oreo decoder can't decode xHE-AAC | **Fixed in v7.1+** (the xHE decoder replaces the plain-AAC slot). On v7.0: update to v7.1 |
| Battery temperature reads 0° in apps | Stock MTK battery driver exposes only the non-standard `batt_temp` sysfs node; healthd reads `temp`, which never exists | Sensor is fine — check a thermal-zone app (e.g. DevCheck's thermal section shows `mtktsbattery`) |
| Some Play-protected app (e.g. Claude) refuses login: "not from Play Store" | Play Integrity on an uncertified GSI fingerprint | Get your fingerprint: `adb shell getprop ro.build.fingerprint` → register it at https://www.google.com/android/uncertified/ → wait up to a few hours → reboot → retry |
| Want stock back | — | Phase 0 backups: `python mtk.py w system your-system-backup.bin` (+ vendor + boot) |
