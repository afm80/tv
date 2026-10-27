import 'package:url_launcher/url_launcher.dart';

/// openExternalPage في الموقع: يفتح الرابط (في الموقع كان يستبدل الصفحة الحالية،
/// وفي التطبيق نفتحه داخل متصفح مدمج ليعود المستخدم للتطبيق بزر الرجوع).
Future<void> openExternalPage(String url, {bool inApp = true}) async {
  Uri uri;
  try {
    uri = Uri.parse(url.trim());
  } catch (_) {
    return;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return;
  try {
    final ok = await launchUrl(
      uri,
      mode: inApp ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication,
    );
    if (!ok && inApp) await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
