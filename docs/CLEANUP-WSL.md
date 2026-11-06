# CLEANUP — removing the WSL build environment completely

The build environment for this ROM was a **WSL2 Alpine** distro used for
image surgery: mount the ext4 image, edit files, unmount, `e2fsck`. Nothing in
this repository requires WSL to *use* the ROM — this is only about reclaiming
the disk and leaving no trace on the machine.

> **This is destructive.** `wsl --unregister` deletes a distro's entire
> filesystem immediately, with no Recycle Bin and no undo. If you have anything
> inside the distro you want to keep, copy it out first.

Run everything in an **elevated** PowerShell (Administrator) unless noted.

---

## 0. See what you actually have

```powershell
wsl --list --verbose
wsl --status
```

Note the exact distro names. This project used one called `alpine`, imported
from a local `.vhdx` rather than installed from the Store — imported distros
live wherever you put the vhdx, not under `%LOCALAPPDATA%\Packages`.

Also check where the disk actually is:

```powershell
Get-ChildItem -Path $env:USERPROFILE, "$env:LOCALAPPDATA", "D:\" -Filter "*.vhdx" -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, @{n='GB';e={[math]::Round($_.Length/1GB,2)}}
```

## 1. Shut WSL down

```powershell
wsl --shutdown
```

This stops every distro and the utility VM. Confirm nothing is still holding
the vhdx — if a file is locked, this step is why.

## 2. Unregister the distro (this deletes it)

```powershell
wsl --unregister alpine
```

Repeat per distro from step 0. `--unregister` removes the registration **and**
deletes the virtual disk. This is the step that actually frees the space.

Verify it is gone:

```powershell
wsl --list --verbose
```

You should see "no installed distributions" (or only ones you meant to keep).

## 3. Remove leftovers

```powershell
# imported-distro folder used by this project
Remove-Item -Recurse -Force "C:\path\to\wsl-alpine" -ErrorAction SilentlyContinue

# WSL's own scratch space
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\wsl" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Temp\wsl*" -ErrorAction SilentlyContinue

# per-user config
Remove-Item -Force "$env:USERPROFILE\.wslconfig" -ErrorAction SilentlyContinue
Remove-Item -Force "$env:USERPROFILE\.wslgconfig" -ErrorAction SilentlyContinue

# Store-installed distros leave package folders behind
Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "*WSL*" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "*Ubuntu*" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "*Debian*" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
```

## 4. Clear the registry traces

`wsl --unregister` removes the distro's own subkey, but the parent key and
stale entries can remain. Check before deleting:

```powershell
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss" /s
```

If nothing you need is listed:

```powershell
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss" /f
```

## 5. Uninstall the WSL app itself

On Windows 11 and recent Windows 10, WSL ships as an app:

```powershell
winget uninstall "Windows Subsystem for Linux"
```

Or: **Settings → Apps → Installed apps → Windows Subsystem for Linux →
Uninstall**.

If you ever installed the old kernel update package, remove it too:
**Settings → Apps → Installed apps → Windows Subsystem for Linux Update**.

## 6. Disable the Windows optional features

Only do this if you do not want WSL back. Both are required for WSL2.

```powershell
dism.exe /online /disable-feature /featurename:Microsoft-Windows-Subsystem-Linux /norestart
dism.exe /online /disable-feature /featurename:VirtualMachinePlatform /norestart
```

Then **reboot**. `VirtualMachinePlatform` is also used by some other
virtualisation tools (Docker Desktop, some Android emulators) — if you use any
of those, leave that one enabled.

## 7. Reclaim the space and verify

```powershell
# confirm the feature is off
dism.exe /online /get-featureinfo /featurename:Microsoft-Windows-Subsystem-Linux | Select-String "State"

# confirm no distros remain
wsl --list --verbose

# confirm no vhdx files are left
Get-ChildItem -Path C:\, D:\ -Filter "*.vhdx" -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, @{n='GB';e={[math]::Round($_.Length/1GB,2)}}
```

`wsl` itself may still respond after step 6 until you reboot — that is normal;
the binary ships with Windows and stays on disk.

---

## If you only wanted the disk space back

You do not have to remove WSL at all. A WSL2 virtual disk **grows but never
shrinks on its own**, so a distro that once held 30 GB of image files keeps
that 30 GB allocated even after the files are deleted.

```powershell
wsl --shutdown

# Windows 11 / recent builds:
wsl --manage <distro> --set-sparse true

# Otherwise, compact manually:
diskpart
  select vdisk file="C:\path\to\ext4.vhdx"
  attach vdisk readonly
  compact vdisk
  detach vdisk
  exit
```

That typically reclaims most of the space while keeping the environment usable.

---

## What this does *not* affect

- **The phone.** Nothing here touches the device, its partitions, or its data.
- **The ROM images.** They are plain files; WSL was only the tool used to edit
  them.
- **This repository.** Everything needed to rebuild is here, and the build
  steps in [BUILD-GUIDE.md](BUILD-GUIDE.md) list the WSL commands used, so the
  environment can be recreated from scratch if you ever want it back.
