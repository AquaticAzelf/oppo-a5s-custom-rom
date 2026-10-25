#!/bin/bash
# Build OMX-flavor xHE-AAC decoder (32-bit) + patched registry + vendor XML overlay
set -eu
P=/c/Users/Azelf/Documents/zcode/xaac-project
TC="$P/ndk/android-ndk-r27b/toolchains/llvm/prebuilt/windows-x86_64/bin"
CC="$TC/clang.exe --target=armv7a-linux-androideabi29"
CXX="$TC/clang++.exe --target=armv7a-linux-androideabi29"
AR="$TC/llvm-ar.exe"
PY=/c/Python314/python.exe
FAV="$P/frameworks_av"
FN="$P/frameworks_native"
SC="$P/system_core"
XAAC="$P/libxaac"
TREES=/c/Users/Azelf/Documents/zcode/work/trees
V27="$TREES/los/lib/vndk-27"
LIB32="$TREES/los/lib"
OUT="$P/out2"
rm -rf "$OUT"; mkdir -p "$OUT/obj"

echo "== [1/5] libxaacdec.a (32-bit) =="
cd "$XAAC"
SRCS=$(awk '/name: "libxaacdec"/{f=1} f&&/srcs:/{s=1;next} s&&/\]/{exit} s{print}' Android.bp \
        | grep -oE '"[a-zA-Z0-9_/.-]+\.c"' | tr -d '"')
# arch.arm block from Android.bp: generic + armv7 selectors + NEON asm
SRCS="$SRCS decoder/generic/ixheaacd_function_selector_generic.c decoder/generic/ixheaacd_qmf_dec_generic.c
decoder/armv7/ixheaacd_qmf_dec_armv7.c decoder/armv7/ixheaacd_fft_armv7.c decoder/armv7/ixheaacd_function_selector_armv7.c"
ASM="decoder/armv7/ixheaacd_overlap_add1.s decoder/armv7/ixheaacd_overlap_add2.s
decoder/armv7/ixheaacd_lap1.s decoder/armv7/ixheaacd_dec_DCT2_64_asm.s
decoder/armv7/ixheaacd_apply_rot.s decoder/armv7/ixheaacd_autocorr_st2.s
decoder/armv7/ixheaacd_auto_corr.s decoder/armv7/ixheaacd_calcmaxspectralline.s
decoder/armv7/ixheaacd_conv_ergtoamplitude.s decoder/armv7/ixheaacd_conv_ergtoamplitudelp.s
decoder/armv7/ixheaacd_cos_sin_mod.s decoder/armv7/ixheaacd_dct3_32.s
decoder/armv7/ixheaacd_decorr_filter2.s decoder/armv7/ixheaacd_enery_calc_per_subband.s
decoder/armv7/ixheaacd_expsubbandsamples.s decoder/armv7/ixheaacd_ffr_divide16.s
decoder/armv7/ixheaacd_fwd_modulation.s decoder/armv7/ixheaacd_harm_idx_zerotwolp.s
decoder/armv7/ixheaacd_imdct_using_fft.s decoder/armv7/ixheaacd_inv_dit_fft_8pt.s
decoder/armv7/ixheaacd_no_lap1.s decoder/armv7/ixheaacd_post_radix_compute2.s
decoder/armv7/ixheaacd_post_radix_compute4.s decoder/armv7/ixheaacd_post_twiddle.s
decoder/armv7/ixheaacd_pre_twiddle_compute.s decoder/armv7/ixheaacd_post_twiddle_overlap.s
decoder/armv7/ixheaacd_radix4_bfly.s decoder/armv7/ixheaacd_rescale_subbandsamples.s
decoder/armv7/ixheaacd_sbr_imdct_using_fft.s decoder/armv7/ixheaacd_sbr_qmfanal32_winadds.s
decoder/armv7/ixheaacd_sbr_qmfsyn64_winadd.s decoder/armv7/ixheaacd_shiftrountine.s
decoder/armv7/ixheaacd_shiftrountine_with_round.s decoder/armv7/ixheaacd_tns_ar_filter_fixed_32x16.s
decoder/armv7/ixheaacd_tns_parcor2lpc_32x16.s decoder/armv7/ixheaacd_esbr_radix4bfly.s
decoder/armv7/ixheaacd_esbr_cos_sin_mod_loop1.s decoder/armv7/ixheaacd_esbr_qmfsyn64_winadd.s
decoder/armv7/ixheaacd_complex_ifft_p2.s decoder/armv7/ixheaacd_complex_fft_p2.s
decoder/armv7/ixheaacd_esbr_cos_sin_mod_loop2.s decoder/armv7/ixheaacd_shiftrountine_with_round_hq.s
decoder/armv7/ixheaacd_mps_complex_fft_64_asm.s decoder/armv7/ixheaacd_esbr_fwd_modulation.s
decoder/armv7/ixheaacd_mps_synt_pre_twiddle.s decoder/armv7/ixheaacd_mps_synt_post_twiddle.s
decoder/armv7/ixheaacd_calc_pre_twid.s decoder/armv7/ixheaacd_calc_post_twid.s
decoder/armv7/ixheaacd_mps_synt_out_calc.s decoder/armv7/ixheaacd_mps_synt_post_fft_twiddle.s
decoder/armv7/ixheaacd_sbr_qmfanal32_winadds_eld.s decoder/armv7/ixheaacd_shiftrountine_with_rnd_eld.s
decoder/armv7/ixheaacd_eld_decoder_sbr_pre_twiddle.s decoder/armv7/ixheaacd_fft_15_ld.s
decoder/armv7/ixheaacd_aac_ld_dec_rearrange.s decoder/armv7/ixheaacd_fft32x32_ld2_armv7.s
decoder/armv7/ixheaacd_apply_scale_fac.s decoder/armv7/ixheaacd_tns_ar_filter_fixed.s"
N=$(echo $SRCS | wc -w); echo "  compiling $N C sources + $(echo $ASM | wc -w) asm..."
for f in $SRCS; do
  o="$OUT/obj/x_$(echo "$f" | tr '/' '_').o"
  $CC -O3 -DANDROID -fPIC -fcommon -mfloat-abi=softfp \
      -Icommon -Idecoder -Idecoder/drc_src -Idecoder/generic -Idecoder/armv7 -c "$f" -o "$o"
done
for f in $ASM; do
  o="$OUT/obj/x_$(echo "$f" | tr '/' '_').o"
  $CC -DANDROID -fPIC -Idecoder/armv7 -c "$f" -o "$o"
done
"$AR" rcs "$OUT/libxaacdec.a" "$OUT"/obj/x_*.o
echo "  libxaacdec.a: $(stat -c %s "$OUT/libxaacdec.a") bytes"

echo "== [2/5] libstagefright_soft_xaacdec.so (32-bit OMX) =="
INC="-I$FAV/media/libstagefright/codecs/xaacdec"
INC="$INC -I$FAV/media/libstagefright/omx/include"
INC="$INC -I$FAV/media/libstagefright/include"
INC="$INC -I$FAV/media/libstagefright/foundation/include"
INC="$INC -I$FAV/include"
INC="$INC -I$FN/headers/media_plugin/media/openmax"
INC="$INC -I$XAAC/common -I$XAAC/decoder -I$XAAC/decoder/drc_src"
INC="$INC -I$SC/libbase/include -I$SC/libcutils/include -I$SC/liblog/include -I$SC/libutils/include -I$SC/libsystem/include"
cd "$FAV/media/libstagefright/codecs/xaacdec"
$CXX -std=gnu++14 -O2 -fPIC -DANDROID -D__ndk1=__1 -fno-rtti $INC \
     -c SoftXAAC.cpp -o "$OUT/obj/omx.o"
# bake Q-era SimpleSoftOMXComponent (Oreo vndk-27 lacks setConfig)
$CXX -std=gnu++14 -O2 -fPIC -DANDROID -D__ndk1=__1 -fno-rtti $INC -c $FAV/media/libstagefright/omx/SimpleSoftOMXComponent.cpp -o "$OUT/obj/ssomx.o"
$CXX -shared -o "$OUT/libstagefright_soft_xaacdec.so" "$OUT/obj/omx.o" "$OUT/obj/ssomx.o" "$OUT/libxaacdec.a" \
  -nostdlib++ \
  -L"$V27" -l:libstagefright_omx.so -l:libstagefright_foundation.so \
  -L"$LIB32" -l:libutils.so -l:libcutils.so -l:liblog.so -l:libc++.so \
  -l:libc.so -l:libm.so -l:libdl.so \
  -Wl,--whole-archive "$P/ndk/android-ndk-r27b/toolchains/llvm/prebuilt/windows-x86_64/lib/clang/18/lib/linux/libclang_rt.builtins-arm-android.a" -Wl,--no-whole-archive \
  -Wl,-soname,libstagefright_soft_xaacdec.so
echo "  component: $(stat -c %s "$OUT/libstagefright_soft_xaacdec.so") bytes"

echo "== [3/5] patch OMX registry (vndk-27, 32-bit) =="
"$PY" - "$V27/libstagefright_omx.so" "$OUT/libstagefright_omx.so" <<'EOF'
data = bytearray(open(r"C:/Users/Azelf/Documents/zcode/work/trees/los/lib/vndk-27/libstagefright_omx.so", "rb").read())
def swap(old, new, expect=None):
    n = data.count(old)
    assert n == 1, f"{old!r}: count {n} != 1"
    assert len(old) == len(new) or len(new) < len(old), f"len {old!r} vs {new!r}"
    i = data.index(old)
    data[i:i+len(new)] = new
    print(f"  {old!r} -> {new!r}")
swap(b"OMX.google.flac.encoder", b"OMX.google.xaac.decoder")
swap(b"audio_encoder.flac\x00", b"audio_decoder.aac\x00")
swap(b"flacenc", b"xaacdec")
open(r"C:/Users/Azelf/Documents/zcode/xaac-project/out2/libstagefright_omx.so", "wb").write(bytes(data))
print("  registry patched")
EOF

C:/Python314/python.exe C:/Users/Azelf/Documents/zcode/scripts/xaac-package.py
echo "ALL DONE"
