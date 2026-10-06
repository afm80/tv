# Alfaham TV

موقع ويب (PWA) لبث قنوات التلفاز، مع لوحة تحكم وبوت يجلب القنوات تلقائياً.

## الملفات
- `index.html` : الموقع (يقرأ الأقسام والقنوات من Firebase)
- `admin.html` : لوحة التحكم (أقسام، قنوات، إعدادات) — عرض القنوات حسب القسم/الدولة مع بحث وصفحات
- `sw.js`, `manifest.json`, `icon-*.png` : تطبيق الويب (PWA)
- `bot/` : بوت جلب القنوات من iptv-org بتحديث تدريجي (يبقي الشغّال ويستبدل/يحذف الميت فقط) وينسّق مع اللوحة (انظر `bot/README.md`)
- `.github/workflows/sync.yml` : تشغيل البوت كل 12 ساعة أو يدوياً

## التشغيل
1. ارفع الملفات إلى مستودع GitHub وفعّل GitHub Pages للموقع.
2. أضف السر `FIREBASE_SERVICE_ACCOUNT` في Settings ← Secrets and variables ← Actions.
3. Actions ← Sync channels ← Run workflow (خانة `dry` = تجربة بدون كتابة).

## تنبيه أمني
لوحة التحكم لا تحتوي تسجيل دخول؛ قيّد الكتابة في قواعد Firebase Realtime Database
بحيث تسمح بالقراءة للجميع والكتابة لحسابك فقط.
