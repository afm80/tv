# تطبيق Alfaham TV (Flutter / أندرويد)

نفس موقع `index.html` بنفس التصميم والمقاسات والسلوك، لكن مبنيّ بـ Flutter ليصبح تطبيق أندرويد حقيقياً.
**لم يتغير شيء في الموقع ولا لوحة التحكم ولا البوت**: التطبيق يقرأ من نفس قاعدة Firebase
(`categories`, `channels`, `settings`, `sidebarLinks`) ويتحدث لحظياً عند أي تعديل، فكل ما تضيفه من اللوحة
أو يضيفه البوت يظهر في التطبيق تلقائياً بلا إعادة بناء.

## أسهل طريقة: بناء الـ APK على GitHub (بدون تثبيت أي شيء)
1. ارفع كل ملفات المشروع إلى مستودعك (يشمل مجلد `app/` وملف `.github/workflows/build-apk.yml`).
2. في المستودع: **Actions ← Build Android APK ← Run workflow**.
3. بعد نحو 10–15 دقيقة افتح **Releases** (يمين صفحة المستودع) ← `Alfaham TV (latest APK)` ← حمّل `AlfahamTV.apk` وثبّته على الجوال.
   (يوجد أيضاً في Actions ← آخر تشغيل ← Artifacts.)

كل رفع جديد لمجلد `app/` يبني نسخة جديدة تلقائياً. التوقيع ثابت، فيمكن تثبيت النسخة الجديدة فوق القديمة دون حذفها.

## البناء على جهازك
```bash
cd app
flutter create --platforms=android --org app.alfaham --project-name tv --no-pub ../_scaffold
cp -r ../_scaffold/android android && rm -rf ../_scaffold
python3 tool/patch_android.py android
mkdir -p ~/.android && cp tool/debug.keystore ~/.android/debug.keystore
flutter pub get
flutter build apk --release        # الناتج: build/app/outputs/flutter-apk/app-release.apk
```

## ما الذي نُقل وكيف
| في الموقع | في التطبيق |
|---|---|
| Firebase JS `on('value')` | `lib/data/rtdb.dart`: قراءة REST + بث مباشر (SSE) من نفس القاعدة |
| `parseChannelLinks`, `getChannelCategoryIds`, ترتيب الأقسام | `lib/data/models.dart`, `lib/data/app_state.dart` (نفس المنطق حرفياً) |
| الشبكة: بطاقة 110px، فجوة 8px، حد أقصى 1200px | `lib/ui/content_grid.dart` |
| الترويسة، الشريط السفلي، القائمة الجانبية (40vw)، البحث | `lib/ui/home_shell.dart`, `lib/ui/search_overlay.dart` |
| المشغل: أزرار الروابط، الرئيسي/الاحتياطي، المحرك، الجودة، إعادة المحاولة | `lib/ui/player_overlay.dart`, `lib/player/player_controller.dart` |
| أيقونات Font Awesome 6.4 وخط Cairo | مضمّنة في `assets/fonts` |

### الفروق الضرورية (بسبب الانتقال من المتصفح إلى تطبيق)
- **المشغل**: بدل مكتبات المتصفح (Video.js / HLS.js / DPlayer / Clappr / Shaka) يستعمل التطبيق محرّكين أصليين:
  **المشغل الرئيسي = ExoPlayer** (مشغل جوجل، الأفضل لبث HLS وتبديل الجودة والبطارية)،
  و**المشغل الاحتياطي = MPV** (يفتح الصيغ والخوادم الصعبة: MPEG-2 وRTMP وUDP وملفات HLS ذات الأخطاء، بتسريع الأجهزة ثم بالفك البرمجي).
  قائمة "المحرك": تلقائي / ExoPlayer / MPV (تسريع) / MPV (برمجي).
  بقية المنطق كما هو: تجربة الرابط ثم نسخة https، ثم الانتقال تلقائياً للاحتياطي، ثم رسالة الفشل مع إعادة المحاولة، وأزرار الروابط تختفي بعد 3.5 ثانية.
  أزرار تحكم ExoPlayer (تشغيل/إيقاف، ملء الشاشة، شريط التقدم أو شارة "مباشر") مبنية يدوياً في `lib/ui/exo_view.dart`.
- **زر "تثبيت التطبيق"** حُذف من القائمة الجانبية (لأنه تطبيق مثبّت أصلاً).
- **الروابط الخارجية** (مباريات اليوم، أقسام بروابط) تُفتح في متصفح مدمج يعود منه زر الرجوع إلى التطبيق؛ روابط التواصل تُفتح في المتصفح.
- أيقونة X: نسخة Font Awesome 6.4 المستعملة في الموقع لا تحتوي شعار X الجديد، فيظهر شعار تويتر القديم بدل فراغ.
- عند الرجوع للتطبيق من الخلفية يُعاد فتح البث ليعود للحظة المباشرة.

## للنشر في Google Play لاحقاً
الملف الحالي موقّع بمفتاح ثابت داخل المستودع (`tool/debug.keystore`) ومناسب للتثبيت المباشر فقط.
للنشر في المتجر أنشئ مفتاحاً خاصاً وخزّنه في GitHub Secrets، ولا تستعمل هذا المفتاح.
اسم الحزمة الحالي `app.alfaham.tv` (من `--org app.alfaham --project-name tv`)؛ عدّله قبل أول نشر لأنه لا يتغير بعدها.
