import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// صفحة ويب داخل التطبيق (أقسام الروابط + مباريات اليوم).
/// - زر الرجوع في الجوال: يرجع داخل الصفحة إن أمكن، وإلا يغلقها.
/// - يدعم ملء شاشة الفيديو (يتحول أفقياً بلا أشرطة نظام ثم يعود).
/// - يمنع النوافذ المنبثقة، ويفتح روابط التطبيقات (tg: / whatsapp: ...) خارجياً.
class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.url});
  final String url;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  InAppWebViewController? _web;
  double _progress = 0;
  String _title = '';
  bool _failed = false;
  bool _fullscreen = false;

  @override
  void dispose() {
    if (_fullscreen) _restoreSystem();
    super.dispose();
  }

  void _restoreSystem() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _onBack() async {
    final web = _web;
    if (web != null && await web.canGoBack()) {
      await web.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: !_fullscreen,
          bottom: !_fullscreen,
          left: !_fullscreen,
          right: !_fullscreen,
          child: Column(
            children: [
              if (!_fullscreen) _topBar(),
              Expanded(
                child: Stack(
                  children: [
                    InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        useShouldOverrideUrlLoading: true,
                        javaScriptCanOpenWindowsAutomatically: false,
                        supportMultipleWindows: false,
                        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                        transparentBackground: false,
                        supportZoom: false,
                      ),
                      onWebViewCreated: (c) => _web = c,
                      onLoadStart: (c, u) {
                        if (_failed) setState(() => _failed = false);
                      },
                      onProgressChanged: (c, p) => setState(() => _progress = p / 100),
                      onTitleChanged: (c, t) {
                        if (mounted) setState(() => _title = t ?? '');
                      },
                      onReceivedError: (c, request, error) {
                        if (request.isForMainFrame == true && mounted) setState(() => _failed = true);
                      },
                      shouldOverrideUrlLoading: (c, action) async {
                        final uri = action.request.url;
                        if (uri == null) return NavigationActionPolicy.ALLOW;
                        final scheme = uri.scheme.toLowerCase();
                        if (scheme == 'http' || scheme == 'https' || scheme == 'about' || scheme == 'blob' || scheme == 'data') {
                          return NavigationActionPolicy.ALLOW;
                        }
                        // روابط التطبيقات (tg:, whatsapp:, ...) تُفتح خارجياً. وintent: يُمنع.
                        if (scheme != 'intent') {
                          try {
                            await launchUrl(Uri.parse(uri.toString()), mode: LaunchMode.externalApplication);
                          } catch (_) {}
                        }
                        return NavigationActionPolicy.CANCEL;
                      },
                      onEnterFullscreen: (c) {
                        setState(() => _fullscreen = true);
                        SystemChrome.setPreferredOrientations(
                            [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
                        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                      },
                      onExitFullscreen: (c) {
                        setState(() => _fullscreen = false);
                        _restoreSystem();
                      },
                    ),
                    if (_progress < 1 && !_failed)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: _progress <= 0 ? null : _progress,
                          minHeight: 3,
                          color: kOrange,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    if (_failed) _errorView(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 46,
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'إغلاق',
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              _title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: cairo(size: 14, weight: 700),
            ),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _web?.reload(),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('⚠ تعذر فتح الصفحة.', style: cairo(size: 14)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              setState(() => _failed = false);
              _web?.reload();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Text('إعادة المحاولة', style: cairo(size: 14, weight: 700, color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }
}
