# PERFORMANCE — every tuning decision, with measurements

This document exists because Android "optimisation" is mostly folklore copied
between forum posts. Everything below was either measured on a real CPH1909 or
rejected with a stated reason. If a claim has no number behind it, it says so.

**Goal:** responsiveness and frame consistency — not benchmark scores. On a
3 GB device the ceiling is eMMC latency and memory bandwidth, not the CPU
scheduler.

---

## 1. Measured baseline (stock kernel, before any tuning)

```
zram compressor        lzo [lz4] deflate zstd     ← lz4 already active
I/O scheduler          noop deadline [cfq]        ← CFQ active (wrong)
vm.swappiness          60
vm.vfs_cache_pressure  100
vm.dirty_ratio         20        (≈600 MB dirty allowed on 3 GB)
vm.dirty_background    5
vm.min_free_kbytes     6520
net.tcp_congestion     cubic
GPU OPP                680 @ 800 mV / 500 @ 700 / 400 @ 650
GPU current            opp 2 = 400 MHz, g_max_limited_idx = 0 (unlimited)
/dev/stune/top-app/    boost=0  capacity_min=0  prefer_idle=0   ← no boost
/proc/filesystems      ext4, exfat, vfat, fuse — **no f2fs**
Display modes          720×1520 @ 59.970005 fps — **the only mode**
```

Three things were actively wrong: **CFQ on eMMC**, **`dirty_ratio=20`**, and
**zero `schedtune` boost**.

---

## 2. Tier A — runtime, free, reversible

Applied at boot by a Magisk `post-fs-data` script. Nothing here needs a
rebuild or a flash.

> **Measured honestly:** these did **not** improve app launch time. `am start -W`
> on Settings went 297 ms → 308 ms median — that is noise. On an idle device
> with 1.3 GB free there is no I/O or memory pressure for them to act on.
> They are a **margin for when pressure arrives**, not a speedup at rest.
> They are kept because they cost nothing and protect the worst case. Do not
> expect to feel them on a freshly booted phone.

### A1 · I/O scheduler CFQ → deadline — highest confidence

CFQ does per-process slice idling, which is pointless on flash and directly
causes the stalls you feel when something writes while you scroll.

```sh
for q in /sys/block/mmcblk0/queue /sys/block/mmcblk1/queue; do
  [ -w "$q/scheduler" ] && echo deadline > "$q/scheduler"
  echo 128 > "$q/read_ahead_kb" 2>/dev/null
  echo 128 > "$q/nr_requests"   2>/dev/null
  echo 0   > "$q/iostats"       2>/dev/null
  echo 1   > "$q/rq_affinity"   2>/dev/null
done
```

Set it on `mmcblk0`, **not `dm-0`** — device-mapper has no scheduler of its own.
Verified working: `noop [deadline] cfq`.

### A2 · `vm.dirty_ratio` 20 → 10 — highest confidence

At 20 % of 3 GB the kernel allows ~600 MB of dirty pages before it throttles.
Flushing that to eMMC is a multi-second freeze.

```sh
sysctl -w vm.dirty_ratio=10
sysctl -w vm.dirty_background_ratio=5
sysctl -w vm.dirty_expire_centisecs=1000    # 10 s, was 30
sysctl -w vm.dirty_writeback_centisecs=200  # 2 s, was 5
```

### A3 · zram-aware VM tuning

`swappiness=60` is a spinning-rust default. When the only swap is compressed
RAM you *want* to swap — it is far cheaper than dropping page cache.

```sh
sysctl -w vm.swappiness=100
sysctl -w vm.page-cluster=0          # no 8-page readahead from zram
sysctl -w vm.watermark_scale_factor=125
sysctl -w vm.min_free_kbytes=16384   # 6.5 MB is very thin for 3 GB
```

### A4 · stune boost

MT6765 is **HMP + WALT, not EAS** — there is no `/sys/kernel/hmp/` interface.
The real lever is `/dev/stune/`. Verified: `top-app` exposes exactly `boost`,
`capacity_min` and `prefer_idle` — **no `uclamp_min`** on this kernel.

```sh
echo 5 > /dev/stune/top-app/schedtune.boost
echo 1 > /dev/stune/top-app/schedtune.prefer_idle
echo 0 > /dev/stune/foreground/schedtune.boost
echo 0 > /dev/stune/background/schedtune.boost
```

Above ~15 the A53s pin at max clock and thermals eat the gain. Never 100.

### A6 · Animation scales → 0.5

Not 0 — zero breaks animation callbacks.

```sh
settings put global window_animation_scale 0.5
settings put global transition_animation_scale 0.5
settings put global animator_duration_scale 0.5
```

### A8 · CFS tunables

Reachable, but modest — they do not change HMP placement, which is where most
jank comes from.

```sh
sysctl -w kernel.sched_latency_ns=10000000
sysctl -w kernel.sched_min_granularity_ns=1500000
sysctl -w kernel.sched_wakeup_granularity_ns=1000000
sysctl -w kernel.sched_tunable_scaling=0
sysctl -w kernel.sched_child_runs_first=1
```

---

## 3. Tier B — baked into the system image

`ro.*` properties cannot change at runtime, so these require an image build
(see [BUILD-GUIDE.md](BUILD-GUIDE.md)). All four verified live after flashing.

### B1 · Triple buffering — the one that actually matters

`ro.surface_flinger.max_frame_buffer_acquired_buffers` defaults to 2. At 3 it
enables `preallocateBuffers()` and triples the RenderEngine buffer cache. On a
weak GPU this is the most reliable smoothness win available, for ~4 MB of RAM.
This is the only graphics change in the project with a clear, physical reason
to work.

### B2 · lmkd

```sh
ro.lmk.kill_heaviest_task=true
ro.lmk.kill_timeout_ms=1000
```

Android 10 uses userspace lmkd. **Never disable it.**

### B3 · Skip the boot animation

`debug.sf.nobootanimation=1` — saves 1–2 s of boot.

### B4 · iorapd — DISABLED, deliberately

`ro.iorapd.enable=false`.

This was tried `true` and **cannot work on this device**. `init` fails
`setgid` to gid 1071 (`EINVAL`) and the service is killed by signal 6 every
5 seconds, forever. Ruled out: the data directory (was `root:root`, fixing
ownership changed nothing) and the binary (run by hand as root, it stays
alive). It is a platform-level privilege refusal, and it cannot be patched
from `/data` because init parses `.rc` files before Magisk mounts anything.

---

## 4. Do NOT do these — verified cargo cult

| "Tweak" | Reality |
|---|---|
| `ro.hwui.texture_cache_size` etc. | **Dead on A10.** Only `use_vulkan` and `render_ahead` are read; caches are screen-sized now |
| `windowsmgr.max_events_per_sec` | Removed long before A10 |
| `debug.sf.latch_unsignaled` | **Not read in android-10.0.0_r47** — no `latch` member exists |
| `debug.sf.high_fps_early_phase_offset_ns` | Android 11+, high-refresh only |
| `vendor.display.*` | Qualcomm QTI props — meaningless on MTK |
| `dalvik.vm.dex2oat-filter` | **Ignored since Android 6** — use `pm.dexopt.*` |
| `persist.sys.ui.hw`, `debug.egl.*`, `debug.egl.swapinterval` | No-ops |
| `data=writeback` | Faster on paper, can expose stale file data after a crash |
| `barrier=0` | Corrupts the journal on power loss |
| `nodelalloc` | Kills delayed allocation — slower |
| `discard` in fstab | Synchronous TRIM on every delete; periodic `fstrim` is cheaper |
| Disabling thermal | Removes the only backstop on a fanless phone |
| `skiavk` globally | Vulkan 1.0 for a 2D workload on 3 GB — and there is no Vulkan driver on this device anyway |
| f2fs for `/data` | **Not in this kernel** (`/proc/filesystems` has no f2fs) |
| `isolcpus` / `nohz_full` | Breaks HMP balancing; `NO_HZ_FULL` isn't compiled in |
| zram `backing_dev` | **Not in kernel 4.9** (added in 4.14) |
| Raising `dalvik.vm.heapgrowthlimit` | Fewer GC pauses, more background kills on 3 GB |
| `max_cached_processes=32` | More warm apps, more memory pressure, more lmkd kills. Counter-productive at 3 GB |
| Disabling `cached_apps_freezer` | Buys ~50–150 ms of resume at the cost of background CPU contention and battery |

---

## 5. Overclocking — the numbers

The OPP table on this device:

| OPP | GPU freq | Voltage | Relative power |
|---|---|---|---|
| 0 | 680 MHz | 800 mV | 746 |
| 1 | 500 MHz | 700 mV | 419 |
| 2 | 400 MHz | 650 mV | 293 |

Power scales roughly `f × V²`, so going 400 → 680 MHz costs **1.7× the clock
for 2.55× the power**. Extrapolating to 730 MHz with the voltage it needs gives
roughly **+11–12 % power for +7.4 % clock**.

| Change | Peak delta | Realistic benefit |
|---|---|---|
| Big cores 2301 → 2501 MHz | +8.7 % | None at rest; thermal-limited under load |
| Little cores 1800 → 1901 MHz | +5.6 % | Same |
| GPU 680 → 730 MHz | +7.4 % | A few FPS in a GPU-bound game, for the first minutes |

**And the ceiling does not move.** The panel has one mode: 59.97 Hz. A game
already running at 60 gains exactly nothing. Overclocking only helps titles
running *below* 60, and only until the thermal governor intervenes — which on
a 12 nm fanless phone is minutes, not hours.

The GPU has an unclamped debug node, `/proc/gpufreq/gpufreq_fixed_freq_volt`
(format `freq_kHz volt_100uV`, `0 0` resets). It is useful for **measuring**
whether an overclock would help you before investing in a kernel build. It
resets on reboot and is not a setting.

> **Never combine `ignore_batt_oc` / `ignore_low_batt` with any overclock.**
> Those guards exist to prevent brown-out shutdowns and cell wear on an aged
> battery, and they cap the GPU for a reason.

---

## 6. Where the ceiling actually is

- **Display:** one mode, 59.97 Hz. Not a tunable.
- **Storage:** eMMC. Random I/O latency dominates app launch, not the scheduler.
- **Memory:** 3 GB with GMS resident at ~120–250 MB. Removing GMS is the single
  biggest remaining win — and a deliberate trade-off, not an oversight.
- **Kernel:** see [KERNEL.md](KERNEL.md). Its theoretical gains are marginal and
  its practical state is "breaks the display".

If you want more from this hardware, buy a faster phone. That is the honest
answer, and it is cheaper than the time spent chasing it.
