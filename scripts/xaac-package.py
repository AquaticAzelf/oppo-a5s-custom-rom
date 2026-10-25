"""Generate clean-insert vendor xml overlay + package final module zip."""
import os
import zipfile

OUT = r"C:/Users/Azelf/Documents/zcode/xaac-project/out2"

# [4/5] xml overlay: insert xaac decoder entry after aac.decoder (clean limits)
src = r"C:/Users/Azelf/Documents/zcode/work/trees/stock_vendor/etc/media_codecs_google_audio.xml"
xml = open(src, encoding="utf-8").read()
entry = (
    '        <MediaCodec name="OMX.google.xaac.decoder" type="audio/mp4a-latm">\n'
    '            <Limit name="channel-count" max="8" />\n'
    '            <Limit name="sample-rate" ranges="7350,8000,11025,12000,16000,22050,'
    '24000,32000,44100,48000,88200,96000" />\n'
    '            <Limit name="bitrate" range="8000-960000" />\n'
    '        </MediaCodec>\n'
)
anchor = '        <MediaCodec name="OMX.google.aac.decoder" type="audio/mp4a-latm">'
i = xml.index(anchor)
j = xml.index("</MediaCodec>", i) + len("</MediaCodec>\n")
xml = xml[:j] + entry + xml[j:]
assert xml.count("OMX.google.xaac.decoder") == 1
with open(os.path.join(OUT, "media_codecs_google_audio.xml"), "w",
          encoding="utf-8", newline="\n") as f:
    f.write(xml)
print("  xml overlay written (clean insert after aac.decoder)")

# [5/5] package module
service = (
    "#!/system/bin/sh\n"
    "( while [ \"$(getprop sys.boot_completed)\" != \"1\" ]; do sleep 2; done\n"
    "  restorecon /system/lib/vndk-27/libstagefright_soft_xaacdec.so"
    " /system/lib/vndk-27/libstagefright_omx.so"
    " /vendor/etc/media_codecs_google_audio.xml\n"
    "  sleep 2\n"
    "  setprop ctl.restart mediacodec ) &\n"
)
z = os.path.join(OUT, "xhe_aac_codec_v7.zip")
with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
    zf.writestr("module.prop",
                "id=xhe_aac_codec\nname=xHE-AAC Decoder (Instagram audio)\n"
                "version=v6\nversionCode=6\nauthor=local-build\n"
                "description=baked SimpleSoftOMXComponent + registry + relabel + restart\n")
    zf.writestr("service.sh", service)
    zf.write(os.path.join(OUT, "libstagefright_soft_xaacdec.so"),
             "system/lib/vndk-27/libstagefright_soft_xaacdec.so")
    zf.write(os.path.join(OUT, "libstagefright_omx.so"),
             "system/lib/vndk-27/libstagefright_omx.so")
    zf.write(os.path.join(OUT, "media_codecs_google_audio.xml"),
             "system/vendor/etc/media_codecs_google_audio.xml")
print(f"  module: {z} ({os.path.getsize(z)} bytes)")
