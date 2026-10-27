import 'util.dart';

class ChannelCategory {
  ChannelCategory({
    required this.id,
    required this.name,
    required this.img,
    required this.link,
    required this.parentId,
    required this.order,
  });

  final String id;
  final String name;
  final String img;
  final String link;
  final String parentId;
  final num order;

  /// يطابق: { id: key, ...value, parentId: String(value.parentId || value.parent || '') }
  factory ChannelCategory.fromJson(String key, Map value) {
    return ChannelCategory(
      id: jsStr(value.containsKey('id') ? value['id'] : key),
      name: jsStr(value['name']),
      img: jsStr(value['img']),
      link: jsStr(value['link']),
      parentId: jsStr(jsTruthy(value['parentId'])
          ? value['parentId']
          : (jsTruthy(value['parent']) ? value['parent'] : '')),
      order: jsNum(value['order']),
    );
  }
}

class ChannelLink {
  const ChannelLink(this.label, this.url);
  final String label;
  final String url;
}

class Channel {
  Channel({
    required this.id,
    required this.name,
    required this.img,
    required this.raw,
    required this.categoryIds,
  });

  final String id;
  final String name;
  final String img;
  final Map raw;
  final List<String> categoryIds;

  /// يطابق: { id: ch.key, ...ch.val() }
  factory Channel.fromJson(String key, Map value) {
    return Channel(
      id: jsStr(value.containsKey('id') ? value['id'] : key),
      name: jsStr(value['name']),
      img: jsStr(value['img']),
      raw: value,
      categoryIds: _categoryIdsOf(value),
    );
  }

  List<ChannelLink> get links => parseChannelLinks(raw);
}

/// getChannelCategoryIds في الموقع: categoryIds ثم categories ثم categoryId ثم catId.
List<String> _categoryIdsOf(Map ch) {
  dynamic ids;
  if (jsTruthy(ch['categoryIds'])) {
    ids = ch['categoryIds'];
  } else if (jsTruthy(ch['categories'])) {
    ids = ch['categories'];
  } else if (jsTruthy(ch['categoryId'])) {
    ids = [ch['categoryId']];
  } else if (jsTruthy(ch['catId'])) {
    ids = [ch['catId']];
  }
  final List list = ids is List ? ids : (ids is Map ? ids.values.toList() : const []);
  return [
    for (final v in list)
      if (v != null && v.toString().isNotEmpty && v.toString() != 'undefined') v.toString()
  ];
}

const List<String> _linkProps = [
  'mainLink', 'hdLink', 'sdLink', 'backupLink', 'url', 'stream', 'src', 'play', 'link', 'video', 'm3u8', 'mp4'
];
const List<String> _priority = ['الرئيسي', 'main', 'auto', 'Auto', 'AUTO'];

/// parseChannelLinks في الموقع: روابط `links` ثم الحقول القديمة، ثم ترتيب الأولوية.
List<ChannelLink> parseChannelLinks(Map ch) {
  final links = <ChannelLink>[];
  final l = ch['links'];
  if (l is Map || l is List) {
    final entries = <MapEntry<String, dynamic>>[];
    if (l is Map) {
      l.forEach((k, v) => entries.add(MapEntry(k.toString(), v)));
    } else if (l is List) {
      for (var i = 0; i < l.length; i++) {
        entries.add(MapEntry('$i', l[i]));
      }
    }
    for (final e in entries) {
      final entry = e.value;
      if (entry is Map && jsTruthy(entry['url'])) {
        links.add(ChannelLink(jsTruthy(entry['label']) ? jsStr(entry['label']) : e.key, jsStr(entry['url'])));
      } else if (entry is String && entry.isNotEmpty) {
        links.add(ChannelLink(e.key, entry));
      }
    }
  }
  for (final prop in _linkProps) {
    final v = ch[prop];
    if (v is String && v.isNotEmpty && !links.any((x) => x.url == v)) {
      links.add(ChannelLink(prop, v));
    }
  }
  int indexOf(String label) => _priority.indexWhere((p) => label.contains(p));
  return stableSorted<ChannelLink>(links, (a, b) {
    final ai = indexOf(a.label);
    final bi = indexOf(b.label);
    if (ai == -1 && bi == -1) return 0;
    if (ai == -1) return 1;
    if (bi == -1) return -1;
    return ai - bi;
  });
}

class SidebarLink {
  SidebarLink({
    required this.name,
    required this.url,
    required this.icon,
    required this.platform,
    required this.order,
  });

  final String name;
  final String url;
  final String icon;
  final String platform;
  final num order;

  factory SidebarLink.fromJson(Map value) => SidebarLink(
        name: jsStr(value['name']),
        url: jsStr(value['url']),
        icon: jsStr(value['icon']),
        platform: jsStr(value['platform']),
        order: jsNum(value['order']),
      );
}

class AppSettings {
  const AppSettings({required this.matchesLink, required this.matchesTitle});
  final String matchesLink;
  final String matchesTitle;
}
