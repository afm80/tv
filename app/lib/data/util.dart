/// مساعدات صغيرة تحاكي سلوك JavaScript المستعمل في الموقع الأصلي.

/// String(value ?? '')
String jsStr(dynamic v) => v == null ? '' : v.toString();

/// قيمة "truthy" كما في JavaScript.
bool jsTruthy(dynamic v) {
  if (v == null || v == false) return false;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true;
}

/// (value || 0) كرقم.
num jsNum(dynamic v) {
  if (v is num) return v.isNaN ? 0 : v;
  if (v is String) return num.tryParse(v.trim()) ?? 0;
  return 0;
}

/// ترتيب مستقر (Array.prototype.sort في JavaScript مستقر، أما List.sort في Dart فلا).
List<T> stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final list = items.toList();
  final idx = List<int>.generate(list.length, (i) => i);
  idx.sort((a, b) {
    final c = compare(list[a], list[b]);
    return c != 0 ? c : a - b;
  });
  return [for (final i in idx) list[i]];
}

/// ترتيب المفاتيح كما يفعل Firebase Realtime Database
/// (المفاتيح الرقمية أولاً تصاعدياً ثم الباقي بالترتيب الحرفي).
int firebaseKeyCompare(String a, String b) {
  final ai = _asInt32(a);
  final bi = _asInt32(b);
  if (ai != null && bi != null) {
    if (ai != bi) return ai.compareTo(bi);
    return a.compareTo(b);
  }
  if (ai != null) return -1;
  if (bi != null) return 1;
  return a.compareTo(b);
}

final RegExp _intKey = RegExp(r'^(0|-?[1-9][0-9]*)$');

int? _asInt32(String s) {
  if (s.length > 11 || !_intKey.hasMatch(s)) return null;
  final v = int.tryParse(s);
  if (v == null || v < -2147483648 || v > 2147483647) return null;
  return v;
}

/// يحوّل قيمة Firebase (Map أو List) إلى مدخلات مرتبة كما يرتبها Firebase.
List<MapEntry<String, dynamic>> firebaseEntries(dynamic value) {
  final out = <MapEntry<String, dynamic>>[];
  if (value is Map) {
    value.forEach((k, v) {
      if (v != null) out.add(MapEntry(k.toString(), v));
    });
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      if (value[i] != null) out.add(MapEntry('$i', value[i]));
    }
  }
  out.sort((a, b) => firebaseKeyCompare(a.key, b.key));
  return out;
}

/// normalizeSearchText في الموقع (بدون NFD لأنه لا يؤثر على العربية هنا).
String normalizeSearchText(String value) {
  var s = value;
  s = s.replaceAll(RegExp('[ً-ٰٟ]'), '');
  s = s.replaceAll(RegExp('[إأآٱ]'), 'ا');
  s = s.replaceAll('ى', 'ي');
  s = s.replaceAll('ة', 'ه');
  return s.toLowerCase().trim();
}
