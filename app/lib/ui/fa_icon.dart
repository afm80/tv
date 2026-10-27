import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../data/util.dart';
import 'fa_codes.dart';

/// أيقونات Font Awesome 6.4 (نفس نسخة الموقع) من الخطوط المرفقة مع التطبيق.
class FaIcon extends StatelessWidget {
  const FaIcon(this.family, this.codePoint, {super.key, this.size = 18, this.color});

  final String family; // FABrands | FASolid | FARegular
  final int codePoint;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      String.fromCharCode(codePoint),
      style: TextStyle(
        fontFamily: family,
        fontSize: size,
        color: color,
        height: 1,
        decoration: TextDecoration.none,
      ),
    );
  }
}

class ResolvedIcon {
  const ResolvedIcon(this.family, this.codePoint);
  final String family;
  final int codePoint;
}

ResolvedIcon _lookup(String style, String name) {
  int? cp;
  switch (style) {
    case 'brands':
      cp = faBrandsCodes[name] ?? (name == 'x-twitter' ? faBrandsCodes['twitter'] : null);
      if (cp != null) return ResolvedIcon('FABrands', cp);
      break;
    case 'regular':
      cp = faRegularCodes[name];
      if (cp != null) return ResolvedIcon('FARegular', cp);
      cp = faSolidCodes[name];
      if (cp != null) return ResolvedIcon('FASolid', cp);
      break;
    default:
      cp = faSolidCodes[name];
      if (cp != null) return ResolvedIcon('FASolid', cp);
  }
  return ResolvedIcon('FASolid', faSolidCodes['link']!);
}

final RegExp _iconClass =
    RegExp(r'^(fab|fas|far|fa-brands|fa-solid|fa-regular)\s+fa-([\w-]+)$', caseSensitive: false);

/// getSidebarIcon في الموقع: الأيقونة المخزنة، ثم المنصة، ثم الدومين، ثم أيقونة رابط.
ResolvedIcon sidebarIconFor(SidebarLink link) {
  final stored = link.icon.trim();
  final m = _iconClass.firstMatch(stored);
  if (m != null) {
    final prefix = m.group(1)!.toLowerCase();
    final style = (prefix == 'fab' || prefix == 'fa-brands')
        ? 'brands'
        : (prefix == 'far' || prefix == 'fa-regular')
            ? 'regular'
            : 'solid';
    return _lookup(style, m.group(2)!.toLowerCase());
  }

  const brandByKey = <String, String>{
    'youtube': 'youtube', 'facebook': 'facebook', 'instagram': 'instagram',
    'tiktok': 'tiktok', 'x': 'x-twitter', 'twitter': 'x-twitter',
    'whatsapp': 'whatsapp', 'telegram': 'telegram', 'snapchat': 'snapchat',
  };
  final platform = link.platform.toLowerCase();
  if (brandByKey.containsKey(platform)) return _lookup('brands', brandByKey[platform]!);
  if (platform == 'store') return _lookup('solid', 'store');

  try {
    final host = Uri.parse(link.url).host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    for (final key in brandByKey.keys) {
      if (host == '$key.com' || host.endsWith('.$key.com')) {
        return _lookup('brands', brandByKey[key]!);
      }
    }
    if (host.contains('store')) return _lookup('solid', 'store');
  } catch (_) {}
  return _lookup('solid', 'link');
}

/// تُستعمل في القائمة الافتراضية عندما لا توجد روابط في قاعدة البيانات.
SidebarLink sidebarLinkFromMap(Map<String, String> m) => SidebarLink(
      name: jsStr(m['name']),
      url: jsStr(m['url']),
      icon: jsStr(m['icon']),
      platform: '',
      order: 0,
    );
