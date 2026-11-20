#!/system/bin/sh
# OPPO A5s custom ROM - boot fix (v1)
# Runs via /data/adb/post-fs-data.d/ at the correct boot moment.
# Keep the phh-GSI audio-effects workaround ON. With effects enabled the
# vendor audio HAL segfaults in libeffects.so (EffectLoadXmlEffectConfig)
# every ~5 s; audioserver/media.audio_policy then never stays up and every
# app that touches audio ANRs ("app isn't responding").
setprop persist.sys.phh.disable_audio_effects 1
setenforce 0
sh /system/bin/zram-init.sh
