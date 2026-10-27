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
write(manifest_path, m)
print("patched AndroidManifest.xml")

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

# ---------------------------------------------------------------- إخفاء شاشة البدء الأصلية (أندرويد 12+)
# أندرويد 12 وما بعده يعرض تلقائياً أيقونة التطبيق في شاشة بدء النظام، ثم تظهر الأيقونة الدائرية من Flutter
# فتظهر أيقونتان. نجعل أيقونة النظام شفافة وخلفيتها سوداء فتبقى الدائرية فقط.
os.makedirs(os.path.join(res_dst, "drawable"), exist_ok=True)
write(
    os.path.join(res_dst, "drawable", "splash_transparent.xml"),
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">\n'
    '    <solid android:color="#00000000"/>\n'
    '    <size android:width="1dp" android:height="1dp"/>\n'
    "</shape>\n",
)
v31_styles = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    "<resources>\n"
    '    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">\n'
    '        <item name="android:windowBackground">@drawable/launch_background</item>\n'
    '        <item name="android:windowSplashScreenBackground">#000000</item>\n'
    '        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_transparent</item>\n'
    '        <item name="android:windowSplashScreenIconBackgroundColor">#000000</item>\n'
    '        <item name="android:windowSplashScreenAnimationDuration">0</item>\n'
    "    </style>\n"
    "</resources>\n"
)
for d in ("values-v31", "values-night-v31"):
    os.makedirs(os.path.join(res_dst, d), exist_ok=True)
    write(os.path.join(res_dst, d, "styles.xml"), v31_styles)
print("hid Android 12+ system splash icon")

# ---------------------------------------------------------------- proguard / gradle
rules = os.path.join(android, "app", "proguard-rules.pro")
write(
    rules,
    "# media_kit يستدعي هذه الأصناف من الكود الأصلي (JNI) فلا يجوز حذفها أو تغيير أسمائها\n"
    "-keep class com.alexmercerind.** { *; }\n"
    "-keep class io.flutter.** { *; }\n"
    "-keep class com.pichillilorenzo.** { *; }\n"
    "-dontwarn com.pichillilorenzo.**\n"
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

# ---------------------------------------------------------------- نافذة عائمة (PiP) وإعدادات البث
# يستعملها زرا "نافذة عائمة" و"بث" في المشغل عبر القناة app.alfaham/native (lib/ui/player_overlay.dart).
m = read(manifest_path)
if "supportsPictureInPicture" not in m:
    m = m.replace("<activity", '<activity\n            android:supportsPictureInPicture="true"', 1)
    write(manifest_path, m)
    print("patched AndroidManifest.xml (PiP)")

kotlin_root = os.path.join(android, "app", "src", "main", "kotlin")
main_activity = None
for root, _dirs, files in os.walk(kotlin_root):
    if "MainActivity.kt" in files:
        main_activity = os.path.join(root, "MainActivity.kt")
        break
if main_activity:
    pkg = re.search(r"^package\s+([\w.]+)", read(main_activity), re.M)
    pkg_line = f"package {pkg.group(1)}\n\n" if pkg else ""
    write(
        main_activity,
        pkg_line
        + """import android.app.PictureInPictureParams
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.alfaham/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            try {
                                val params = PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational(16, 9))
                                    .build()
                                enterPictureInPictureMode(params)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("pip", e.message, null)
                            }
                        } else {
                            result.error("pip", "unsupported", null)
                        }
                    }
                    "openCast" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_CAST_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("cast", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
""",
    )
    print("wrote MainActivity.kt (PiP + cast settings)")
else:
    print("WARNING: MainActivity.kt not found; PiP/cast buttons will show a message")
