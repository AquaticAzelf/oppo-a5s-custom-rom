#!/system/bin/sh
# 20-perf.sh — runtime performance tuning for OPPO A5s (CPH1909)
#
# Deploy to /data/adb/post-fs-data.d/20-perf.sh  (chmod 755)
# Runs early enough to affect the whole boot, after /data is mounted.
#
# Every line is idempotent and guarded: if the node does not exist on this
# kernel, the write is skipped instead of failing the script.
#
# Evidence for each choice is in README.md §4.2. Nothing here needs a rebuild.

LOG=/data/local/tmp/perf-tune.log
exec >>"$LOG" 2>&1
echo "=== $(date) perf-tune ==="

w() {  # w <path> <value>
    [ -e "$1" ] || { echo "skip (absent): $1"; return; }
    echo "$2" > "$1" 2>/dev/null && echo "set $1 = $2" || echo "FAIL $1 = $2"
}

# ---------------------------------------------------------------- I/O (A1)
# CFQ does per-process slice idling, which is pointless on flash and causes
# multi-hundred-ms stalls when something writes while the UI scrolls.
# deadline gives bounded latency. Set on the real device, NOT on dm-0.
for dev in mmcblk0 mmcblk1; do
    q="/sys/block/$dev/queue"
    [ -d "$q" ] || continue
    # only switch if deadline is actually offered
    case "$(cat "$q/scheduler" 2>/dev/null)" in
        *deadline*) w "$q/scheduler" deadline ;;
        *)          echo "skip: $dev has no deadline" ;;
    esac
    w "$q/read_ahead_kb" 128
    w "$q/nr_requests"   128
    w "$q/iostats"       0
    w "$q/rq_affinity"   1
    w "$q/rotational"    0
done

# ------------------------------------------------------------- memory (A2/A3)
# dirty_ratio 20 on 3 GB allows ~600 MB dirty before throttling; flushing that
# to eMMC is a multi-second freeze.
w /proc/sys/vm/dirty_ratio            10
w /proc/sys/vm/dirty_background_ratio 5
w /proc/sys/vm/dirty_expire_centisecs   1000
w /proc/sys/vm/dirty_writeback_centisecs 200

# zram is the only swap; compressed RAM is far cheaper than dropping page cache
w /proc/sys/vm/swappiness            100
w /proc/sys/vm/page-cluster            0
w /proc/sys/vm/watermark_scale_factor 125
w /proc/sys/vm/min_free_kbytes       16384

# --------------------------------------------------------------- stune (A4)
# MT6765 is HMP+WALT, not EAS — there is no /sys/kernel/hmp. This is the lever.
# Above ~15 the A53s pin at max and thermals eat the gain.
w /dev/stune/top-app/schedtune.boost       5
w /dev/stune/top-app/schedtune.prefer_idle 1
w /dev/stune/foreground/schedtune.boost    0
w /dev/stune/background/schedtune.boost    0

# ----------------------------------------------------------------- CFS (A8)
# sched_tunable_scaling=0 first, or the kernel rescales these by log2(nCPU).
w /proc/sys/kernel/sched_tunable_scaling      0
w /proc/sys/kernel/sched_latency_ns            10000000
w /proc/sys/kernel/sched_min_granularity_ns    1500000
w /proc/sys/kernel/sched_wakeup_granularity_ns 1000000
w /proc/sys/kernel/sched_child_runs_first      1

echo "=== done ==="
