import 'package:flutter/material.dart';

const Color kOrange = Color(0xFFFF6600);
const Color kOrangeLight = Color(0xFFFF8C00);
const Color kAmber = Color(0xFFFFC107);

/// خط Cairo (خط الموقع). الملف متغير الوزن، لذلك نمرّر محور wght صراحةً.
TextStyle cairo({
  double size = 14,
  int weight = 400,
  Color color = Colors.white,
  double? height,
  List<Shadow>? shadows,
}) {
  return TextStyle(
    fontFamily: 'Cairo',
    fontSize: size,
    fontWeight: _weightOf(weight),
    fontVariations: [FontVariation('wght', weight.toDouble())],
    color: color,
    height: height,
    shadows: shadows,
    decoration: TextDecoration.none,
  );
}

FontWeight _weightOf(int w) {
  if (w <= 100) return FontWeight.w100;
  if (w <= 200) return FontWeight.w200;
  if (w <= 300) return FontWeight.w300;
  if (w <= 400) return FontWeight.w400;
  if (w <= 500) return FontWeight.w500;
  if (w <= 600) return FontWeight.w600;
  if (w <= 700) return FontWeight.w700;
  if (w <= 800) return FontWeight.w800;
  return FontWeight.w900;
}
