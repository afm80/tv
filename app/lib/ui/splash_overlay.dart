import 'package:flutter/material.dart';

/// صورة الأيقونة المنبثقة (للبدء فقط، منفصلة عن أيقونة التطبيق): ضع ملفك هنا بهذا الاسم.
const String _kSplashImage = 'assets/images/splash.png';
const String _kFallbackImage = 'assets/images/icon-512.png';

/// شاشة بدء قصيرة: أيقونة دائرية تنبثق (تكبر بحركة ارتدادية) ثم تتلاشى الشاشة كلها.
/// تظهر مرة واحدة فقط عند تشغيل التطبيق (تُنشأ في main.dart ولا تعود حتى يُعاد تشغيله).
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.onDone});

  /// تُستدعى بعد انتهاء التلاشي ليُزال الغطاء من الشجرة.
  final VoidCallback onDone;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> with SingleTickerProviderStateMixin {
  static const int _popMs = 750; // الانبثاق
  static const int _holdMs = 650; // بقاء الأيقونة
  static const int _fadeMs = 350; // التلاشي

  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _iconOpacity;
  late final Animation<double> _bgOpacity;

  @override
  void initState() {
    super.initState();
    const total = _popMs + _holdMs + _fadeMs;
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: total));
    _scale = Tween<double>(begin: 0.2, end: 1).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0, _popMs / total, curve: Curves.easeOutBack)),
    );
    _iconOpacity = CurvedAnimation(parent: _c, curve: const Interval(0, 0.12, curve: Curves.easeOut));
    _bgOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _c, curve: Interval((_popMs + _holdMs) / total, 1, curve: Curves.easeIn)),
    );
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Opacity(
          opacity: _bgOpacity.value,
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: Opacity(
                opacity: _iconOpacity.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: Container(
                    width: 148,
                    height: 148,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6600).withOpacity(.35),
                          blurRadius: 36,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        _kSplashImage,
                        fit: BoxFit.cover,
                        // إن لم توجد صورة البدء بعد، نستعمل أيقونة التطبيق.
                        errorBuilder: (_, __, ___) => Image.asset(_kFallbackImage, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
