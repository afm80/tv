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
res_src = os.path.join(here, "android_res")
res_dst = os.path.join(android, "app", "src", "main", "res")
for d in sorted(os.listdir(res_src)):
    src_dir = os.path.join(res_src, d)
    dst_dir = os.path.join(res_dst, d)
    os.makedirs(dst_dir, exist_ok=True)
    for f in os.listdir(src_dir):
        shutil.copy2(os.path.join(src_dir, f), os.path.join(dst_dir, f))
# إن كان القالب يستعمل أيقونة تكيفية (anydpi-v26) فإنها تتقدم على الأيقونات أعلاه، نحذفها.
for d in os.listdir(res_dst):
    if d.startswith("mipmap-anydpi"):
        shutil.rmtree(os.path.join(res_dst, d), ignore_errors=True)
print("copied launcher icons")

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
