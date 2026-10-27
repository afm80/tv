// الإعدادات الثابتة — نفس القيم الموجودة في index.html الأصلي.

const String kAppName = 'Alfaham TV';

/// قاعدة بيانات Firebase Realtime Database (نفس التي يقرأ منها الموقع ولوحة التحكم والبوت).
const String kDatabaseUrl = 'https://alfaham-tv-1980-default-rtdb.firebaseio.com';

const String kDefaultMatchesLink = 'https://www.yala-sport-now.com';
const String kDefaultMatchesTitle = 'مباريات اليوم';

/// خلفية الموقع وشعار الترويسة (نفس الروابط في الموقع).
const String kBackgroundUrl = 'https://h.top4top.io/p_3784nirj21.png';
const String kLogoUrl =
    'https://raw.githubusercontent.com/h-80/img/refs/heads/main/Alfahamtv2.png';

/// صور محلية تُستعمل عند فشل الصورة (DEFAULT_IMAGE في الموقع) أو عند عدم الاتصال.
const String kDefaultImageAsset = 'assets/images/icon-192.png';
const String kBrandImageAsset = 'assets/images/icon-1024.png';
const String kLogoAsset = 'assets/images/logo.png';

/// مهلة انتظار بدء التشغيل لكل محاولة (الموقع: 4500ms للمتصفح؛ هنا أطول قليلاً للجوال).
const Duration kEngineTimeout = Duration(seconds: 8);

/// نفس تعريف defaultSidebarLinks في الموقع.
const List<Map<String, String>> kDefaultSidebarLinks = [
  {'name': 'YouTube', 'icon': 'fab fa-youtube', 'url': 'https://www.youtube.com/@alfahaminfo'},
  {'name': 'Facebook', 'icon': 'fab fa-facebook', 'url': 'https://web.facebook.com/alfahaminfo1'},
  {'name': 'Instagram', 'icon': 'fab fa-instagram', 'url': 'https://www.instagram.com/alfahaminfo'},
  {'name': 'TikTok', 'icon': 'fab fa-tiktok', 'url': 'https://www.tiktok.com/@alfaham.info'},
  {'name': 'X', 'icon': 'fab fa-x-twitter', 'url': 'https://x.com/alfahaminfo'},
  {'name': 'WhatsApp', 'icon': 'fab fa-whatsapp', 'url': 'https://whatsapp.com/channel/0029VbCa4Nd2P59l7LFa7B3j'},
  {'name': 'Telegram', 'icon': 'fab fa-telegram', 'url': 'https://t.me/alfahaminfo1'},
  {'name': 'Alfaham Store', 'icon': 'fas fa-store', 'url': 'https://alfahamstore.apk.com/'},
];
