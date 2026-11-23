@echo off
REM OPPO A5s GSI repack - one-click boot-fix installer
REM Use after any factory reset: enable USB debugging + Root debugging,
REM plug the phone, double-click this file.
REM If adb is not on PATH, set the ADB variable to its full path first.
if not defined ADB set "ADB=adb"
echo Waiting for device...
%ADB% wait-for-device
%ADB% root
ping -n 4 127.0.0.1 > nul
REM Create the directory BEFORE pushing, or the first push fails.
%ADB% shell "mkdir -p /data/adb/post-fs-data.d"
%ADB% push "%~dp0fix.sh" /data/adb/post-fs-data.d/fix.sh
REM Tier-A runtime tuning from docs/PERFORMANCE.md - deployed as 20-perf.sh.
%ADB% push "%~dp0perf-tune.sh" /data/adb/post-fs-data.d/20-perf.sh
%ADB% shell "chmod 755 /data/adb/post-fs-data.d/fix.sh /data/adb/post-fs-data.d/20-perf.sh"
%ADB% shell "restorecon /data/adb/post-fs-data.d/fix.sh /data/adb/post-fs-data.d/20-perf.sh"
%ADB% shell "setenforce 0"
%ADB% shell "sh /system/bin/zram-init.sh"
echo.
echo Fix installed and applied. Reboot the phone to confirm.
pause
