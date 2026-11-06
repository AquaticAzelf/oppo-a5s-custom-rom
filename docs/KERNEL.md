# KERNEL — the custom kernel, and why it is parked

A custom kernel **boots Android on this phone in 74 seconds** — encrypted
`/data` on `dm-0`, Magisk root, Wi-Fi, modules, zram, framework up. Everything
works **except the panel**: it runs at roughly 1 FPS with tearing, flicker and
wrong geometry, and `SurfaceFlinger: Faking VSYNC due to driver stall` repeats
at 1 Hz.

This document records what was proven, what was eliminated, and what a future
attempt would need — so nobody re-walks the dead ends.

**Best build:** `boot-v8.0-nomask.img`, kernel marker `adf25d91…1298`.
Not shipped. The stock kernel drives the panel perfectly, and every
optimisation that survives measurement works on it.

---

## Why a custom kernel was attempted at all

Not for FPS — the panel is 59.97 Hz and the stock kernel already reaches it
(see [PERFORMANCE.md](PERFORMANCE.md) §5). The intended gains were scheduling
and VM behaviour that the stock kernel does not expose:

| Item | Verdict |
|---|---|
| `CONFIG_BALANCE_ANON_FILE_RECLAIM` | Present in OPPO's factory kernel, missing from our tree. Most plausible real gain — memory reclaim under pressure |
| `CONFIG_HZ_300` | 3.3 ms tick vs 4 ms. Marginal |
| BORE scheduler | **No 4.9 branch exists.** Oldest legacy port is 4.4. Porting to MTK's 318 KB `fair.c` means manual conflict resolution in `update_curr`, `dequeue_task_fair`, `wakeup_preempt_entity`. Zero published ARM measurements |
| CPU overclock | **Likely net negative** — voltage and heat on 12 nm, sustained clocks drop once thermal trips |
| GPU 730 MHz | +7.4 %, and `g_max_limited_idx = 0` says it is not even being limited. Reachable at runtime; do not bake |
| PowerVR DDK 1.13 / Vulkan | **Impossible** — the device has no Vulkan ICD and never shipped one. Kernel and userspace are build-ID paired anyway |

That is a thin list. The honest summary is that the kernel was a low-expected-value
project, and the display bug made it a negative one.

---

## ⚠ If you rebuild from this tree

> **Any kernel built from this source MUST keep the ext4 `async_discard` patch
> in `fs/ext4/super.c`.**

Without it `/data` silently falls back to a 512 MB tmpfs — no crypto state, no
zygote, no framework, and the phone sits at the logo forever. This was a
two-week wall. The patch adds `Opt_async_discard` to the option enum, the token
table, and the match handler (returning `1`). If you build from public OPPO
source, it is **not** there and must be re-applied.

The cause: the vendor fstab passes `async_discard` for `/data` and `/cache`.
`async_discard` is an MTK extension. Stock OPPO's kernel understands it; a
rebuilt mainline-derived tree does not, so `ext4_fill_super` returns `-1` and
the mount fails.

Also: this source tree has **no `fs/exfat` at all**, so exFAT SD cards will not
mount on a custom kernel. The stock kernel has it.

---

## What is proven

| Fact | Evidence |
|---|---|
| Custom kernel boots Android | `boot_completed=1`, 74 s |
| `/data` mounts on the real encrypted partition | `/dev/block/dm-0 on /data type ext4` |
| Modules, Wi-Fi, Magisk, zram all work | 7 modules, `wlan0` up, `30.7:MAGISK:R` |
| **The display fault is ours, not the hardware** | stock logs **0** `Faking VSYNC`; ours is continuous |
| The kernel draws a correct picture | `screencap` returns the lock screen rendered perfectly |

That last row matters: the frame *content* is right, it is the *timing* that is
broken. The compositor is producing correct images; they are simply not being
presented.

---

## What has been eliminated — do not re-test

Device tree (**byte-identical**) · GPU DDK (both `1.9@4971894`) · GPU
clock/thermal/CPU-bound · auto-brightness · backlight · ramdisk · fstab
contents · kernel cmdline · `CONFIG_BLK_DEV_DM` / `DM_CRYPT` / all
`CONFIG_CRYPTO_*` · TEE/keymaster · **all display config options (identical to
factory)** · OVL layer config (**dump identical to working stock**) · DSI PHY
timing registers (**byte-identical**) · display clocks (**both 228,499,954 Hz**)
· VFP blanking margin (236 → 320, no change) · IRQ storm (masked, 30,000/s →
63/s, no change) · idle manager (disabled at runtime, no change) · shadow
registers (no change) · OVL bypass (no change) · panel timing/PLL (360 MHz is
exact for 63.0 Hz and matches OPPO's own published source).

Each of those was a real hypothesis with a real test. All negative.

---

## The measured fault chain

```
dsi0 buffer underrun  (~1 per frame) + input relay unfinish
   → ovl0 abnormal SOF → ovl0 hw reset done
   → RDMA start ≈ 1,285–2,112, end = 2   (frames begin, almost none complete)
   → frame_done never fires
   → DISP_PATH_EVENT_IF_VSYNC never fires
   → SurfaceFlinger fakes vsync at 1 Hz
```

Also reproducible: `_ovl_fence_release_callback` logs
`disp ovl status error!! stat=0x5` (`primary_display.c:3289`). Bit 0 of
`DISP_REG_OVL_STA` is `STA_FLD_RUN` — the OVL is still running when it is
reconfigured. **That same line is a second, ungated `primary_display_diagnose()`
call site** — gate it next time or the log fills again.

Two changes that did land, and are worth keeping in any future build:

- Removed the unconditional `primary_display_diagnose()` after
  `DDPERR("buffer underrun")` in `ddp_dsi.c` — exactly one gated call remains
- `BUFFER_UNDERRUN_INT_EN` 1 → 0

They cut an IRQ storm from **30,000/s to 63/s** and boot time from **310 s to
74 s** — but the display did not improve, which is itself diagnostic: the
underruns were a symptom, not the cause.

---

## The conclusion

Every register, clock and configuration that can be compared is **identical to
the working stock kernel**. What differs is the **compiled display code**: this
source tree is older than the one OPPO shipped in March 2021.

**Lead, not conclusion:** stock carries a newer CMDQ/MDP
(`CMDQ_IOCTL_ASYNC_EXEC`, `ASYNC_WAIT`, `ALLOC_READBACK_SLOTS`,
`mdp_ioctl_ex.c`) that this tree lacks. CMDQ times display register writes, so
an older implementation is a plausible reason configs land mid-frame and the
OVL hardware-resets. Caveat: the display stack normally drives CMDQ *inside*
the kernel, so this may not touch the display path at all. It is the strongest
lead, not a proven cause.

**Remaining lead:** the `DSI_START` register — stock `0x00010001`, ours
`0x00000001`. Bit 16 is `VM_CMD_START`, set on stock and clear on ours. That is
the only unexplained configuration difference found.

**To go further** you need either the matching 2021 OPPO source (not published)
or reverse-engineering stock's display functions instruction by instruction.
That is a multi-session job with no guarantee of success.

---

## If you want to continue

1. Re-apply the `async_discard` patch first, or nothing else matters.
2. Diff the `DSI_START` write path. That register is the only known delta.
3. Compare CMDQ ioctl implementations between stock and this tree.
4. Keep the IRQ-storm fixes; they are independently useful.

Do not spend time on clocks, PHY registers, OVL config or the device tree.
Those are byte-identical and have been tested repeatedly.
