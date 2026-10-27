import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// يحوّل أي قيمة صورة مخزنة في القاعدة إلى رابط http(s) صالح،
/// بنفس تسامح المتصفح (مسافات، //host، مسارات نسبية، host بدون بروتوكول، أحرف عربية/مسافات).
/// يُرجع null إذا كانت data: URI أو قيمة فارغة/غير صالحة.
String? resolveImageUrl(String raw) {
  var s = raw.trim();
  // قيم أُدخلت يدوياً: علامات اقتباس حول الرابط، أو أسطر/تبويبات داخله.
  if (s.length > 1 &&
      ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'")))) {
    s = s.substring(1, s.length - 1).trim();
  }
  if (s.isEmpty || s.startsWith('data:')) return null;
  s = s.replaceAll(RegExp(r'[\r\n\t]'), '');
  // المتصفح يعامل \ كأنها / في روابط http.
  if (s.contains('\\')) s = s.replaceAll('\\', '/');
  if (s.startsWith('//')) {
    s = 'https:$s';
  } else if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(s)) {
    // host بدون بروتوكول (مثل i.imgur.com/a.png) وليس ملفاً نسبياً (مثل iq.png أو flags/iq.png).
    final hostLike = RegExp(r'^[^/\s.]+(\.[^/\s.]+)+(:\d+)?/', caseSensitive: false).hasMatch(s) &&
        !RegExp(r'^[^/]*\.(png|jpe?g|gif|webp|svg|avif)/', caseSensitive: false).hasMatch(s);
    if (!hostLike) {
      // مسار نسبي للموقع (مثل ./flags/iq.png).
      s = Uri.parse(kSiteBase).resolve(s).toString();
    } else {
      s = 'https://$s';
    }
  }
  try {
    // Uri.parse يشفّر المسافات والأحرف غير ASCII كما يفعل المتصفح.
    final u = Uri.parse(s);
    if (u.scheme != 'http' && u.scheme != 'https') return null;
    return u.toString();
  } catch (_) {
    try {
      return Uri.encodeFull(s);
    } catch (_) {
      return null;
    }
  }
}

Uint8List? _dataUriBytes(String raw) {
  final s = raw.trim();
  if (!s.startsWith('data:')) return null;
  final i = s.indexOf(',');
  if (i < 0) return null;
  final meta = s.substring(0, i);
  final body = s.substring(i + 1);
  if (meta.contains(';base64')) {
    // قد يحتوي النص مسافات/أسطر، أو %XX، أو base64 بصيغة URL-safe.
    var b = body.replaceAll(RegExp(r'\s'), '');
    if (b.contains('%')) {
      try {
        b = Uri.decodeComponent(b);
      } catch (_) {}
    }
    b = b.replaceAll('-', '+').replaceAll('_', '/');
    try {
      return base64.decode(base64.normalize(b));
    } catch (_) {
      return null;
    }
  }
  try {
    return Uint8List.fromList(utf8.encode(Uri.decodeComponent(body)));
  } catch (_) {
    return Uint8List.fromList(utf8.encode(body));
  }
}

/// هل البايتات ملف SVG؟ (المتصفح يعرضه، أما Image في فلاتر فلا يفك ترميزه).
bool _looksLikeSvg(Uint8List b) {
  final n = b.length < 1024 ? b.length : 1024;
  final head = String.fromCharCodes(b.sublist(0, n)).toLowerCase();
  return head.contains('<svg');
}

/// يعرض بايتات صورة: SVG عبر flutter_svg والباقي عبر Image.memory.
class _BytesImage extends StatelessWidget {
  const _BytesImage({required this.bytes, required this.fit, required this.cacheWidth, required this.fallback});

  final Uint8List bytes;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    if (_looksLikeSvg(bytes)) {
      return SvgPicture.memory(bytes, fit: fit, width: double.infinity, height: double.infinity);
    }
    return Image.memory(
      bytes,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

/// محاولة إنقاذ: إذا فشل التحميل العادي (SVG، رأس Referer مرفوض، http/https…)
/// نجلب البايتات يدوياً بعدة صيغ ونعرضها بأنفسنا.
class _RescueImage extends StatefulWidget {
  const _RescueImage({required this.url, required this.fit, required this.cacheWidth, required this.fallback});

  final String url;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget fallback;

  static final Map<String, Future<Uint8List?>> _inflight = {};

  static Future<Uint8List?> fetch(String url) {
    if (_inflight.length > 300) _inflight.remove(_inflight.keys.first);
    return _inflight.putIfAbsent(url, () => _fetch(url)).then((v) {
      if (v == null) _inflight.remove(url); // الفشل لا يُخزَّن لنسمح بإعادة المحاولة لاحقاً.
      return v;
    });
  }

  static Future<Uint8List?> _fetch(String url) async {
    final ua = {'User-Agent': SmartImage._headers['User-Agent']!, 'Accept': '*/*'};
    final attempts = <MapEntry<String, Map<String, String>>>[];

    // أعلام flagcdn.com: بعض الشبكات/الحمايات ترفض طلبات التطبيقات، فنجرّب مرآة بديلة (SVG) أولاً.
    final flag = RegExp(r'flagcdn\.com/(?:w\d+|h\d+|\d+x\d+)/([a-z]{2}(?:-[a-z]+)?)\.(?:png|webp|jpg|svg)', caseSensitive: false)
        .firstMatch(url);
    if (flag != null) {
      final code = flag.group(1)!.toLowerCase();
      attempts.add(MapEntry('https://cdn.jsdelivr.net/gh/lipis/flag-icons/flags/4x3/$code.svg', ua));
    }
    attempts.add(MapEntry(url, ua));
    attempts.add(MapEntry(url, const {}));
    if (url.startsWith('http://')) attempts.add(MapEntry('https://${url.substring(7)}', ua));
    // آخر محاولة: وسيط صور عام يجلب الصورة نيابةً عن التطبيق ويحوّلها إلى PNG
    // (يحل حجب الطلبات، وAVIF/SVG، وبصمة TLS التي ترفضها بعض الخدمات).
    attempts.add(MapEntry('https://wsrv.nl/?url=${Uri.encodeComponent(url)}&w=400&output=png', const {}));

    for (final a in attempts) {
      try {
        final res = await http.get(Uri.parse(a.key), headers: a.value).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) return res.bodyBytes;
      } catch (_) {}
    }
    return null;
  }

  @override
  State<_RescueImage> createState() => _RescueImageState();
}

class _RescueImageState extends State<_RescueImage> {
  late Future<Uint8List?> _future = _RescueImage.fetch(widget.url);

  @override
  void didUpdateWidget(covariant _RescueImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _future = _RescueImage.fetch(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox.expand();
        final bytes = snap.data;
        if (bytes == null) return widget.fallback;
        return _BytesImage(bytes: bytes, fit: widget.fit, cacheWidth: widget.cacheWidth, fallback: widget.fallback);
      },
    );
  }
}

/// صورة بطاقة تعمل مع كل صيغ الروابط التي يقبلها المتصفح في الموقع.
class SmartImage extends StatelessWidget {
  const SmartImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.fallback,
  });

  final String url;
  final BoxFit fit;
  final int? memCacheWidth;
  final Widget? fallback;

  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
    // بدون avif: فلاتر لا يفك ترميزه، والخدمات تعيده للمتصفحات التي تعلن دعمه.
    'Accept': 'image/webp,image/apng,image/png,image/jpeg,image/gif,image/svg+xml,image/*;q=0.8,*/*;q=0.5',
    'Referer': kSiteBase,
  };

  @override
  Widget build(BuildContext context) {
    final fb = fallback ?? Image.asset(kDefaultImageAsset, fit: fit);
    final bytes = _dataUriBytes(url);
    if (bytes != null) {
      return _BytesImage(bytes: bytes, fit: fit, cacheWidth: memCacheWidth, fallback: fb);
    }
    final resolved = resolveImageUrl(url);
    if (resolved == null) return fb;
    return CachedNetworkImage(
      imageUrl: resolved,
      httpHeaders: _headers,
      fit: fit,
      memCacheWidth: memCacheWidth,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => const SizedBox.expand(),
      errorWidget: (_, __, ___) => _RescueImage(url: resolved, fit: fit, cacheWidth: memCacheWidth, fallback: fb),
    );
  }
}
