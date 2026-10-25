#!/bin/sh
# Build xHE-AAC (c2.android.xaac.decoder) for LineageOS 17.1 swcodec flattened apex.
# Runs in Alpine WSL with Linux NDK r27b. Output: Magisk module zip on /mnt/c.
set -eu
C=/mnt/c/Users/Azelf/Documents/zcode
P=$C/xaac-project
NDK=/root/android-ndk-r27b
TC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
CC=$TC/aarch64-linux-android29-clang
CXX=$TC/aarch64-linux-android29-clang++
AR=$TC/llvm-ar
FAV=$P/frameworks_av
SC=$P/system_core
XAAC=$P/libxaac
APEX=$C/work/trees/los/apex/com.android.media.swcodec
ALIB=$APEX/lib64
OUT=$P/out
rm -rf "$OUT"
mkdir -p "$OUT/obj"

echo "== [1/5] libxaacdec.a (static, from Android.bp srcs) =="
cd "$XAAC"
SRCS=$(awk '/name: "libxaacdec"/{f=1} f&&/srcs:/{s=1;next} s&&/\]/{exit} s{print}' Android.bp \
        | grep -oE '"[a-zA-Z0-9_/.-]+\.c"' | tr -d '"')
N=$(echo $SRCS | wc -w)
echo "  compiling $N sources..."
[ "$N" -gt 10 ] || { echo "FATAL: srcs extraction found too few files"; exit 1; }
for f in $SRCS; do
  o="$OUT/obj/xaac_$(echo "$f" | tr '/' '_').o"
  $CC -O3 -DLOUDNESS_LEVELING_SUPPORT -DANDROID -fPIC \
      -Icommon -Idecoder -Idecoder/drc_src -c "$f" -o "$o"
done
$AR rcs "$OUT/libxaacdec.a" "$OUT"/obj/xaac_*.o
echo "  libxaacdec.a: $(stat -c %s "$OUT/libxaacdec.a") bytes"

echo "== [2/5] libcodec2_soft_xaacdec.so =="
cd "$FAV/media/codec2/components/xaac"
INC="-I. -I$FAV/media/codec2/core/include -I$FAV/media/codec2/include \
     -I$FAV/media/codec2/components/base/include \
     -I$FAV/media/codec2/vndk/include -I$FAV/include"
INC="$INC -I$SC/libbase/include -I$SC/libcutils/include -I$SC/liblog/include -I$SC/libutils/include"
$CXX -std=c++14 -O2 -fPIC -DANDROID $INC -c C2SoftXaacDec.cpp -o "$OUT/obj/comp.o"
$CXX -shared -o "$OUT/libcodec2_soft_xaacdec.so" "$OUT/obj/comp.o" "$OUT/libxaacdec.a" \
  -L"$ALIB" -l:libcodec2.so -l:libcodec2_vndk.so -l:libcodec2_soft_common.so \
  -l:libstagefright_foundation.so -l:libsfplugin_ccodec_utils.so \
  -l:libbase.so -l:libutils.so -l:libcutils.so -l:liblog.so -l:libc++.so \
  -Wl,--no-undefined -Wl,-soname,libcodec2_soft_xaacdec.so
echo "  component .so: $(stat -c %s "$OUT/libcodec2_soft_xaacdec.so") bytes"

echo "== [3/5] binary-patch codec store (encoder name -> xaac, equal length) =="
python3 - "$ALIB/libcodec2_vndk.so" "$OUT/libcodec2_vndk.so" <<'EOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
data = bytearray(open(src, 'rb').read())
target = b"libcodec2_soft_xaacdec.so"
names = sorted(set(re.findall(rb"libcodec2_soft_[a-z0-9_]+\.so", data)))
cands = [n for n in names if len(n) == len(target) and n.endswith(b"enc.so")]
if not cands:
    sys.exit("FATAL: no equal-length encoder string to sacrifice: " + repr(names))
victim = cands[0]
assert data.count(victim) == 1, "victim not unique"
i = data.index(victim)
data[i:i+len(victim)] = target
open(dst, 'wb').write(data)
print(f"  replaced {victim.decode()} -> {target.decode()}")
EOF

echo "== [4/5] media_codecs.xml with xaac entry =="
python3 - "$APEX/etc/media_codecs.xml" "$OUT/media_codecs.xml" <<'EOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
xml = open(src, encoding='utf-8').read()
entry = '''        <MediaCodec name="c2.android.xaac.decoder" type="audio/mp4a-latm">
            <Limit name="channel-count" max="8" />
            <Limit name="sample-rate" ranges="7350,8000,11025,12000,16000,22050,24000,32000,44100,48000,88200,96000" />
            <Limit name="bitrate" range="8000-960000" />
        </MediaCodec>
'''
i = xml.find('<MediaCodec name="c2.android.aac.decoder"')
assert i > 0, "aac decoder entry not found"
j = xml.find('</MediaCodec>', i) + len('</MediaCodec>\n')
xml = xml[:j] + entry + xml[j:]
assert 'c2.android.xaac.decoder' in xml
open(dst, 'w', encoding='utf-8', newline='\n').write(xml)
print("  xml entry inserted after c2.android.aac.decoder")
EOF

echo "== [5/5] package Magisk module =="
python3 - "$OUT" <<'EOF'
import sys, zipfile, os
out = sys.argv[1]
mod = "system/apex/com.android.media.swcodec"
files = [
    (f"{mod}/lib64/libcodec2_soft_xaacdec.so", f"{out}/libcodec2_soft_xaacdec.so"),
    (f"{mod}/lib64/libcodec2_vndk.so",         f"{out}/libcodec2_vndk.so"),
    (f"{mod}/etc/media_codecs.xml",            f"{out}/media_codecs.xml"),
]
prop = ("id=xhe_aac_codec\nname=xHE-AAC Decoder (Instagram audio)\n"
        "version=v1.0\nversionCode=1\nauthor=local-build\n"
        "description=c2.android.xaac.decoder for Android 10 swcodec apex\n")
zpath = f"{out}/xhe_aac_codec.zip"
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("module.prop", prop)
    for arc, disk in files:
        z.write(disk, arc)
print(f"  module: {zpath} ({os.path.getsize(zpath)} bytes)")
EOF
echo "ALL DONE"
