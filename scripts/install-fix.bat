@echo off
REM OPPO A5s custom ROM - one-click boot-fix installer
REM Use after any factory reset: enable USB debugging + Root debugging,
REM plug the phone, double-click this file.
set ADB=E:\stuff\platform-tools\adb.exe
echo Waiting for device...
%ADB% wait-for-device
%ADB% root
ping -n 4 127.0.0.1 > nul
%ADB% push "%~dp0fix.sh" /data/adb/post-fs-data.d/fix.sh
%ADB% shell "mkdir -p /data/adb/post-fs-data.d"
%ADB% push "%~dp0fix.sh" /data/adb/post-fs-data.d/fix.sh
%ADB% shell "chmod 755 /data/adb/post-fs-data.d/fix.sh"
%ADB% shell "restorecon /data/adb/post-fs-data.d/fix.sh"
%ADB% shell "setenforce 0"
%ADB% shell "sh /system/bin/zram-init.sh"
echo.
echo Fix installed and applied. Reboot the phone to confirm.
pause
