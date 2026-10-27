#!/usr/bin/env python3
"""يعدّل مجلد android الذي ينشئه `flutter create` ليناسب تطبيق Alfaham TV:
صلاحية الإنترنت، السماح بروابط http، اسم التطبيق، أيقونة التطبيق، خلفية سوداء، وقواعد proguard.

الاستعمال: python3 tool/patch_android.py <مسار مجلد android>
"""
import os
import re
import shutil
import sys

android = sys.argv[1] if len(sys.argv) > 1 else "android"
here = os.path.dirname(os.path.abspath(__file__))
app_label = "Alfaham TV"


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


# ---------------------------------------------------------------- AndroidManifest
manifest_path = os.path.join(android, "app", "src", "main", "AndroidManifest.xml")
m = read(manifest_path)

perms = ""
for p in ("android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE"):
    if p not in m:
        perms += f'    <uses-permission android:name="{p}"/>\n'

queries = ""
if "<queries>" not in m:
    queries = (
        "    <queries>\n"
        '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>\n'
        '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="http"/></intent>\n'
        "    </queries>\n"
    )

if perms or queries:
    m = re.sub(r"(\s*)<application", lambda mo: "\n" + perms + queries + "    <application", m, count=1)

m = re.sub(r'android:label="[^"]*"', f'android:label="{app_label}"', m, count=1)
if "usesCleartextTraffic" not in m:
    m = m.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
if "supportsPictureInPicture" not in m:
    m = m.replace("<activity", '<activity\n            android:supportsPictureInPicture="true"', 1)
write(manifest_path, m)
print("patched AndroidManifest.xml")

# ---------------------------------------------------------------- MainActivity (نافذة عائمة PiP)
main_dir = os.path.join(android, "app", "src", "main")
act_path = None
for root, _dirs, files in os.walk(main_dir):
    for f in files:
        if f in ("MainActivity.kt", "MainActivity.java"):
            act_path = os.path.join(root, f)
if act_path:
    pkg = re.search(r"^package\s+([\w.]+)", read(act_path), re.M).group(1)
    if act_path.endswith(".java"):
        os.remove(act_path)
        act_path = act_path[:-5] + ".kt"
    write(
        act_path,
        f"""package {pkg}

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {{
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alfaham/pip")
        pipChannel!!.setMethodCallHandler {{ call, result ->
            if (call.method == "enter") {{
                if (Build.VERSION.SDK_INT >= 26) {{
                    try {{
                        enterPictureInPictureMode(
                            PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
                        )
                        result.success(true)
                    }} catch (e: Exception) {{
                        result.success(false)
                    }}
                }} else {{
                    result.success(false)
                }}
            }} else {{
                result.notImplemented()
            }}
        }}
    }}

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {{
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }}
}}
""",
    )
    print("wrote MainActivity.kt with PiP channel")
else:
    print("WARNING: MainActivity not found, PiP skipped")

# ---------------------------------------------------------------- أيقونة التطبيق
# نولّدها وقت البناء من icon-1024.png الموجودة في المستودع (لا ملفات ثنائية مرفوعة).
res_dst = os.path.join(android, "app", "src", "main", "res")
repo_root = os.path.abspath(os.path.join(here, "..", ".."))
source_icon = None
for cand in (
    os.path.join(repo_root, "icon-1024.png"),
    os.path.join(here, "..", "assets", "images", "icon-1024.png"),
):
    if os.path.exists(cand):
        source_icon = cand
        break
try:
    from PIL import Image

    if source_icon is None:
        raise RuntimeError("icon-1024.png not found")
    img = Image.open(source_icon).convert("RGBA")
    for d, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        out_dir = os.path.join(res_dst, "mipmap-" + d)
        os.makedirs(out_dir, exist_ok=True)
        img.resize((size, size), Image.LANCZOS).save(os.path.join(out_dir, "ic_launcher.png"), optimize=False)
    # إن كان القالب يستعمل أيقونة تكيفية (anydpi-v26) فإنها تتقدم على الأيقونات أعلاه، نحذفها.
    for d in os.listdir(res_dst):
        if d.startswith("mipmap-anydpi"):
            shutil.rmtree(os.path.join(res_dst, d), ignore_errors=True)
    print("generated launcher icons from", source_icon)
except Exception as e:  # الأيقونة ليست سبباً لفشل البناء: نترك أيقونة Flutter الافتراضية
    print("WARNING: launcher icons skipped:", e)

# ---------------------------------------------------------------- شاشة البدء سوداء
for root, _dirs, files in os.walk(res_dst):
    for f in files:
        if not f.endswith(".xml"):
            continue
        p = os.path.join(root, f)
        t = read(p)
        n = t.replace("@android:color/white", "@android:color/black").replace(
            "Theme.Light.NoTitleBar", "Theme.Black.NoTitleBar"
        )
        if n != t:
            write(p, n)
            print("dark launch:", os.path.relpath(p, android))

# ---------------------------------------------------------------- proguard / gradle
rules = os.path.join(android, "app", "proguard-rules.pro")
write(
    rules,
    "# media_kit يستدعي هذه الأصناف من الكود الأصلي (JNI) فلا يجوز حذفها أو تغيير أسمائها\n"
    "-keep class com.alexmercerind.** { *; }\n"
    "-keep class io.flutter.** { *; }\n"
    "-dontwarn com.google.android.play.core.**\n",
)

for name, line in (
    ("build.gradle.kts", '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")\n'),
    ("build.gradle", "            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'\n"),
):
    p = os.path.join(android, "app", name)
    if not os.path.exists(p):
        continue
    t = read(p)
    if "proguard-rules.pro" in t:
        break
    t2, n = re.subn(r"(release\s*\{\s*\n)", lambda mo: mo.group(1) + line, t, count=1)
    if n:
        write(p, t2)
        print("patched", name)
    else:
        print("WARNING: could not find release block in", name)
    break
