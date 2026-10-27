import 'package:flutter/material.dart';

/// خلفية الموقع والتطبيق: صورة محلية (تدرّج من الأسود إلى الرمادي الداكن)، لا تعتمد على أي رابط خارجي.
class SiteBackground extends StatelessWidget {
  const SiteBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Color(0xFF2E2E2E)],
          ),
        ),
        child: Image.asset(
          'assets/images/background.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => const SizedBox.expand(),
        ),
      ),
    );
  }
}
