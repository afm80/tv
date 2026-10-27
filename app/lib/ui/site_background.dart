import 'package:flutter/material.dart';

import '../config.dart';
import 'smart_image.dart';

/// خلفية الموقع: body { background: url(...) center / cover no-repeat fixed }.
/// إن تعذّر تحميل الرابط (حجب/حذف الصورة) نستعمل assets/images/background.jpg إن وُجدت،
/// وإلا تدرّج داكن بدل أن تبقى الشاشة فارغة.
class SiteBackground extends StatelessWidget {
  const SiteBackground({super.key});

  static const _gradient = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF1A0D00), Colors.black, Color(0xFF0A0A0A)],
        stops: [0, .55, 1],
      ),
    ),
    child: SizedBox.expand(),
  );

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: SmartImage(
          url: kBackgroundUrl,
          fallback: Image.asset(
            'assets/images/background.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _gradient,
          ),
        ),
      ),
    );
  }
}
