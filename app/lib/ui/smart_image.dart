import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// يحوّل أي قيمة صورة مخزنة في القاعدة إلى رابط http(s) صالح،
/// بنفس تسامح المتصفح (مسافات، //host، مسارات نسبية، host بدون بروتوكول، أحرف عربية/مسافات).
/// يُرجع null إذا كانت data: URI أو قيمة فارغة/غير صالحة.
String? resolveImageUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty || s.startsWith('data:')) return null;
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
  try {
    final meta = s.substring(0, i);
    final body = s.substring(i + 1);
    if (meta.contains(';base64')) return base64.decode(base64.normalize(Uri.decodeComponent(body).replaceAll(RegExp(r'\s'), '')));
    return Uint8List.fromList(utf8.encode(Uri.decodeComponent(body)));
  } catch (_) {
    return null;
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
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    'Referer': kSiteBase,
  };

  @override
  Widget build(BuildContext context) {
    final fb = fallback ?? Image.asset(kDefaultImageAsset, fit: fit);
    final bytes = _dataUriBytes(url);
    if (bytes != null) {
      return Image.memory(bytes, fit: fit, cacheWidth: memCacheWidth, gaplessPlayback: true, errorBuilder: (_, __, ___) => fb);
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
      errorWidget: (_, __, ___) => fb,
    );
  }
}
