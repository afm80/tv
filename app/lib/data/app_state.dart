import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import 'models.dart';
import 'rtdb.dart';
import 'util.dart';

/// حالة التطبيق: تحاكي المتغيرات العامة في index.html
/// (categoriesCache, channelsCache, currentStack, currentChannelId, ...).
class AppState extends ChangeNotifier {
  // ----- البيانات -----
  Map<String, ChannelCategory> categories = {};
  List<Channel> channels = [];
  Map<String, List<Channel>> _channelsByCategory = {};
  List<SidebarLink> sidebarLinks = [];
  AppSettings settings =
      const AppSettings(matchesLink: kDefaultMatchesLink, matchesTitle: kDefaultMatchesTitle);

  bool loaded = false;
  bool _gotCategories = false;
  bool _gotChannels = false;

  // ----- التنقل -----
  List<String> stack = [];
  Channel? currentChannel;
  bool sidebarOpen = false;
  bool searchOpen = false;

  final List<RtdbValueStream> _streams = [];
  Timer? _loadTimeout;

  void start() {
    if (_streams.isNotEmpty) return;
    _streams.addAll([
      RtdbValueStream('categories', _onCategories),
      RtdbValueStream('channels', _onChannels),
      RtdbValueStream('settings', _onSettings),
      RtdbValueStream('sidebarLinks', _onSidebarLinks),
    ]);
    for (final s in _streams) {
      s.start();
    }
    // إن تعذّر الاتصال نعرض الواجهة الفارغة كما يفعل الموقع عند الخطأ.
    _loadTimeout = Timer(const Duration(seconds: 12), () {
      if (!loaded) {
        loaded = true;
        notifyListeners();
      }
    });
  }

  void reconnect() {
    for (final s in _streams) {
      s.reconnect();
    }
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    for (final s in _streams) {
      s.stop();
    }
    super.dispose();
  }

  // ----- استقبال البيانات -----

  void _checkLoaded() {
    if (!loaded && _gotCategories && _gotChannels) {
      loaded = true;
      _loadTimeout?.cancel();
    }
  }

  void _onCategories(dynamic value) {
    final map = <String, ChannelCategory>{};
    for (final e in firebaseEntries(value)) {
      final v = e.value;
      if (v is Map) {
        final c = ChannelCategory.fromJson(e.key, v);
        map[e.key] = c;
      }
    }
    categories = map;
    _gotCategories = true;
    _checkLoaded();
    notifyListeners();
  }

  void _onChannels(dynamic value) {
    final list = <Channel>[];
    final byCat = <String, List<Channel>>{};
    for (final e in firebaseEntries(value)) {
      final v = e.value;
      if (v is Map) {
        final ch = Channel.fromJson(e.key, v);
        list.add(ch);
        if (ch.id.isEmpty) continue;
        for (final cid in ch.categoryIds.toSet()) {
          (byCat[cid] ??= []).add(ch);
        }
      }
    }
    channels = list;
    _channelsByCategory = byCat;
    _gotChannels = true;
    _checkLoaded();
    notifyListeners();
  }

  void _onSettings(dynamic value) {
    final data = value is Map ? value : const {};
    settings = AppSettings(
      matchesLink: jsTruthy(data['matchesLink']) ? jsStr(data['matchesLink']) : kDefaultMatchesLink,
      matchesTitle: jsTruthy(data['matchesTitle']) ? jsStr(data['matchesTitle']) : kDefaultMatchesTitle,
    );
    notifyListeners();
  }

  void _onSidebarLinks(dynamic value) {
    final list = <SidebarLink>[];
    for (final e in firebaseEntries(value)) {
      final v = e.value;
      if (v is Map && jsTruthy(v['name']) && jsTruthy(v['url'])) {
        list.add(SidebarLink.fromJson(v));
      }
    }
    sidebarLinks = stableSorted<SidebarLink>(list, (a, b) => a.order.compareTo(b.order));
    notifyListeners();
  }

  // ----- استعلامات العرض (renderCurrentView) -----

  String? get currentCategoryId => stack.isEmpty ? null : stack.last;

  /// الأقسام الفرعية للقسم [parentId] ('' = الجذر) مرتبة حسب order.
  List<ChannelCategory> childrenOf(String parentId) {
    return stableSorted<ChannelCategory>(
      categories.values.where((c) => c.parentId == parentId),
      (a, b) => a.order.compareTo(b.order),
    );
  }

  List<Channel> channelsIn(String categoryId) => _channelsByCategory[categoryId] ?? const [];

  // ----- التنقل -----

  void pushCategory(String id) {
    noLinkMessage = false;
    stack = [...stack, id];
    notifyListeners();
  }

  /// نتيجة بحث عن قسم: stack = [id] كما في الموقع.
  void jumpToCategory(String id) {
    noLinkMessage = false;
    stack = [id];
    currentChannel = null;
    notifyListeners();
  }

  void popCategory() {
    if (stack.isEmpty) return;
    stack = stack.sublist(0, stack.length - 1);
    notifyListeners();
  }

  void goHome() {
    noLinkMessage = false;
    stack = [];
    currentChannel = null;
    notifyListeners();
  }

  void openChannel(Channel ch) {
    if (ch.links.isEmpty) {
      // نفس رسالة الموقع عند عدم وجود رابط صالح.
      noLinkMessage = true;
      notifyListeners();
      return;
    }
    noLinkMessage = false;
    currentChannel = ch;
    notifyListeners();
  }

  bool noLinkMessage = false;

  void closePlayer() {
    if (currentChannel == null) return;
    currentChannel = null;
    notifyListeners();
  }

  void setSidebar(bool open) {
    if (sidebarOpen == open) return;
    sidebarOpen = open;
    notifyListeners();
  }

  void setSearch(bool open) {
    if (searchOpen == open) return;
    searchOpen = open;
    if (open) sidebarOpen = false;
    notifyListeners();
  }

  /// هل يوجد شيء يمكن الرجوع عنه قبل الخروج من التطبيق؟
  bool get canGoBack => searchOpen || sidebarOpen || currentChannel != null || stack.isNotEmpty;

  /// زر الرجوع في أندرويد (يقابل history.back / popstate في الموقع).
  void back() {
    noLinkMessage = false;
    if (searchOpen) {
      searchOpen = false;
    } else if (sidebarOpen) {
      sidebarOpen = false;
    } else if (currentChannel != null) {
      currentChannel = null;
    } else if (stack.isNotEmpty) {
      stack = stack.sublist(0, stack.length - 1);
    }
    notifyListeners();
  }
}
