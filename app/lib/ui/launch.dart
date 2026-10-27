import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'web_page.dart';

/// مفتاح الملاح العام: يسمح بفتح صفحات من أي مكان دون الحاجة إلى context.
final GlobalKey<NavigatorState> appNavKey = GlobalKey<NavigatorState>();

/// openExternalPage في الموقع.
/// - inApp = true (الافتراضي): يفتح الرابط داخل التطبيق (أقسام الروابط، مباريات اليوم، نتائج البحث).
/// - inApp = false: يفتح التطبيق الخارجي مباشرة (روابط التواصل في القائمة الجانبية).
Future<void> openExternalPage(String url, {bool inApp = true}) async {
  Uri uri;
  try {
    uri = Uri.parse(url.trim());
  } catch (_) {
    return;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return;

  if (inApp) {
    final nav = appNavKey.currentState;
    if (nav != null) {
      await nav.push(MaterialPageRoute<void>(builder: (_) => WebPage(url: uri.toString())));
      return;
    }
  }
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  } catch (_) {}
}
