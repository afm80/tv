import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../config.dart';
import '../data/models.dart';

/// المشغل الرئيسي / الاحتياطي (satKidsPlayerMode في الموقع).
enum PlayerMode { primary, backup }

/// اختيار المحرك (satEngineSelect). في الموقع محركات المتصفح (Video.js/HLS.js/...)،
/// وفي التطبيق محركان على نفس مشغل MPV: تسريع الأجهزة أو فك برمجي.
enum EngineChoice { auto, hw, sw }

class QualityLevel {
  const QualityLevel(this.label, this.url, this.bandwidth);
  final String label;
  final String url;
  final int bandwidth;
}

const String kUserAgent =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.0.0 Mobile Safari/537.36';

final RegExp _fatalError = RegExp(
  r'(failed to open|failed to recognize|unrecognized file format|server returned|http error|'
  r'connection (refused|timed out|reset)|invalid data found|no such file|\b(401|403|404|410|500|502|503)\b)',
  caseSensitive: false,
);

/// buildUrlVariants في الموقع: الرابط نفسه ثم نسخة https إن كان http.
List<String> buildUrlVariants(String url) {
  final variants = <String>[url];
  if (RegExp(r'^http://', caseSensitive: false).hasMatch(url)) {
    final u = url.replaceFirst(RegExp(r'^http:', caseSensitive: false), 'https:');
    if (!variants.contains(u)) variants.add(u);
  }
  return variants;
}

/// يقابل منطق المشغل في index.html (satPlayVideo / satPlayBackupVideo / satFallbackCycle ...).
class SatPlayerController extends ChangeNotifier {
  SatPlayerController({required this.channelName, required this.links});

  final String channelName;
  final List<ChannelLink> links;

  int linkIndex = 0;

  Player? player;
  VideoController? video;

  bool loading = false;
  bool failureVisible = false;
  String failureText = '⚠ تعذر تشغيل القناة حالياً.';
  VoidCallback? _failureRetry;

  String msg = '';
  bool get showRetry => msg.startsWith('⚠');

  PlayerMode mode = PlayerMode.primary;
  EngineChoice engine = EngineChoice.auto;

  List<QualityLevel> qualities = [];
  int qualityIndex = 0;

  String activeUrl = '';
  String _currentPlayUrl = '';
  int fallbackCycle = 0;
  int _token = 0;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---------------------------------------------------------------- واجهة عامة

  void start() {
    if (links.isEmpty) return;
    playVideo(links[0].url);
  }

  /// الضغط على أحد أزرار الروابط (link-chip).
  void selectLink(int index) {
    if (index < 0 || index >= links.length) return;
    linkIndex = index;
    engine = EngineChoice.auto;
    _notify();
    playVideo(links[index].url);
  }

  void setEngine(EngineChoice e) {
    engine = e;
    _notify();
    if (activeUrl.isNotEmpty) playVideo(activeUrl);
  }

  void choosePrimary() {
    _setMode(PlayerMode.primary);
    if (activeUrl.isNotEmpty) playVideo(activeUrl);
  }

  void chooseBackup() {
    _setMode(PlayerMode.backup);
    if (activeUrl.isNotEmpty) playBackup(activeUrl);
  }

  /// زر ↻ بجانب الرسالة (satRetryKidsBtn).
  void retry() {
    fallbackCycle = 0;
    if (activeUrl.isEmpty) return;
    if (mode == PlayerMode.backup) {
      playBackup(activeUrl);
    } else {
      playVideo(activeUrl);
    }
  }

  /// زر "إعادة المحاولة" داخل شاشة الفشل.
  void retryFromFailure() {
    failureVisible = false;
    _notify();
    final cb = _failureRetry;
    if (cb != null) cb();
  }

  /// عند العودة من الخلفية: نعيد فتح البث ليعود للحظة المباشرة.
  void onAppResumed() {
    final p = player;
    if (p == null || _currentPlayUrl.isEmpty || loading || _disposed) return;
    unawaited(p.open(Media(_currentPlayUrl), play: true).catchError((_) {}));
  }

  Future<void> selectQuality(int index) async {
    if (index < 0 || index >= qualities.length) return;
    qualityIndex = index;
    final p = player;
    if (p == null) return;
    _currentPlayUrl = qualities[index].url;
    _notify();
    try {
      await p.open(Media(_currentPlayUrl), play: true);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- المشغل الرئيسي

  Future<void> playVideo(String url, {bool automatic = false}) async {
    final token = await _reset();
    if (token != _token) return;
    activeUrl = url;
    if (!automatic) fallbackCycle = 0;
    _setMode(PlayerMode.primary);
    _setLoading(true);

    final all = [EngineChoice.hw, EngineChoice.sw];
    final order = engine == EngineChoice.auto
        ? all
        : [engine, ...all.where((e) => e != engine)];

    for (final variant in buildUrlVariants(url)) {
      for (final e in order) {
        if (token != _token) return;
        final ok = await _attempt(variant, e, token);
        if (token != _token) return;
        if (ok) {
          _onPlaying(variant, token);
          return;
        }
      }
    }
    if (token != _token) return;

    if (fallbackCycle == 0) {
      fallbackCycle = 1;
      _showMsg('⚠ تعذر التشغيل، جاري الانتقال للمشغل الاحتياطي...');
      Timer(const Duration(milliseconds: 500), () {
        if (!_disposed && token == _token && activeUrl == url) playBackup(url);
      });
    } else {
      _setLoading(false);
      _showFailure('⚠ تعذر تشغيل رابط البث بالمشغلين المتاحين.', () {
        playVideo(activeUrl, automatic: true);
      });
    }
  }

  // ---------------------------------------------------------------- المشغل الاحتياطي

  Future<void> playBackup(String url) async {
    final token = await _reset();
    if (token != _token) return;
    activeUrl = url;
    _setMode(PlayerMode.backup);
    _setLoading(true);

    for (final variant in buildUrlVariants(url)) {
      if (token != _token) return;
      final ok = await _attempt(variant, EngineChoice.sw, token, backup: true);
      if (token != _token) return;
      if (ok) {
        _currentPlayUrl = variant;
        _setLoading(false);
        failureVisible = false;
        _notify();
        return;
      }
    }
    if (token != _token) return;
    _setLoading(false);
    _showFailure('⚠ فشل المشغل الاحتياطي، جاري الرجوع للمشغل الرئيسي...', () {
      playVideo(activeUrl, automatic: true);
    });
    Timer(const Duration(milliseconds: 1200), () {
      if (!_disposed && activeUrl == url && mode == PlayerMode.backup) {
        playVideo(activeUrl, automatic: true);
      }
    });
  }

  // ---------------------------------------------------------------- داخلي

  void _onPlaying(String url, int token) {
    if (token != _token) return;
    _currentPlayUrl = url;
    loading = false;
    failureVisible = false;
    _notify();
    unawaited(_loadLevels(url, token));
  }

  /// محاولة تشغيل واحدة (محرك + رابط). ترجع true إذا بدأ التشغيل فعلاً.
  Future<bool> _attempt(String url, EngineChoice choice, int token, {bool backup = false}) async {
    await _disposePlayer();
    if (token != _token) return false;

    final p = Player();
    final c = VideoController(
      p,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: choice == EngineChoice.hw && !backup,
      ),
    );
    if (token != _token) {
      unawaited(p.dispose());
      return false;
    }
    player = p;
    video = c;
    _notify();

    await _configure(p, backup: backup);
    if (token != _token) return false;

    final done = Completer<bool>();
    void finish(bool ok) {
      if (!done.isCompleted) done.complete(ok);
    }

    final subs = <StreamSubscription<dynamic>>[
      p.stream.position.listen((pos) {
        if (pos > const Duration(milliseconds: 300) && !p.state.buffering) finish(true);
      }),
      p.stream.error.listen((e) {
        if (_fatalError.hasMatch(e)) finish(false);
      }),
      p.stream.completed.listen((v) {
        if (v) finish(false);
      }),
    ];
    final timer = Timer(kEngineTimeout, () => finish(false));

    try {
      await p.open(Media(url), play: true);
    } catch (_) {
      finish(false);
    }

    final ok = await done.future;
    timer.cancel();
    for (final s in subs) {
      unawaited(s.cancel());
    }
    return ok && token == _token;
  }

  Future<void> _configure(Player p, {required bool backup}) async {
    final pf = p.platform;
    if (pf == null) return;
    final d = pf as dynamic;
    Future<void> setProp(String key, String value) async {
      try {
        await d.setProperty(key, value);
      } catch (_) {}
    }

    await setProp('user-agent', kUserAgent);
    await setProp('network-timeout', '15');
    await setProp('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
    if (backup) {
      await setProp('cache', 'yes');
      await setProp('demuxer-readahead-secs', '20');
    }
  }

  Future<int> _reset() async {
    _token++;
    final token = _token;
    await _disposePlayer();
    qualities = [];
    qualityIndex = 0;
    msg = '';
    failureVisible = false;
    loading = false;
    _notify();
    return token;
  }

  Future<void> _disposePlayer() async {
    final p = player;
    if (p == null) return;
    player = null;
    video = null;
    _notify();
    // نترك إطاراً واحداً على الأقل ليزول عنصر الفيديو من الشاشة قبل إتلاف المشغل.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      await p.dispose();
    } catch (_) {}
  }

  void _setMode(PlayerMode m) {
    if (mode == m) return;
    mode = m;
    _notify();
  }

  void _setLoading(bool v) {
    loading = v;
    if (v) failureVisible = false;
    _notify();
  }

  void _showMsg(String text) {
    msg = text;
    _notify();
  }

  void _showFailure(String text, VoidCallback retry) {
    failureText = text;
    _failureRetry = retry;
    failureVisible = true;
    loading = false;
    _notify();
  }

  // ---------------------------------------------------------------- قائمة الجودة (HLS)

  Future<void> _loadLevels(String url, int token) async {
    if (mode != PlayerMode.primary) return;
    try {
      final res = await http
          .get(Uri.parse(url), headers: {'User-Agent': kUserAgent})
          .timeout(const Duration(seconds: 8));
      if (token != _token || res.statusCode != 200) return;
      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (!body.contains('#EXT-X-STREAM-INF')) return;

      final base = Uri.parse(url);
      final levels = <QualityLevel>[];
      final lines = const LineSplitter().convert(body);
      final attrRe = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
        final attrs = <String, String>{};
        for (final m in attrRe.allMatches(line.substring(line.indexOf(':') + 1))) {
          var v = m.group(2) ?? '';
          if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) v = v.substring(1, v.length - 1);
          attrs[m.group(1)!] = v;
        }
        var j = i + 1;
        while (j < lines.length && (lines[j].trim().isEmpty || lines[j].trim().startsWith('#'))) {
          j++;
        }
        if (j >= lines.length) break;
        final uri = base.resolve(lines[j].trim()).toString();
        final bandwidth = int.tryParse(attrs['BANDWIDTH'] ?? '') ?? 0;
        int? height;
        final resolution = attrs['RESOLUTION'];
        if (resolution != null && resolution.contains('x')) height = int.tryParse(resolution.split('x').last);
        levels.add(QualityLevel(_qualityLabel(attrs['NAME'], height, bandwidth, levels.length), uri, bandwidth));
      }
      if (levels.length < 2 || token != _token) return;
      levels.sort((a, b) => a.bandwidth.compareTo(b.bandwidth));
      qualities = levels;
      _notify();
    } catch (_) {}
  }

  /// satQualityLabel في الموقع.
  String _qualityLabel(String? name, int? height, int bitrate, int index) {
    if (name != null && name.isNotEmpty) return name;
    if (height != null && height > 0) return '${height}p';
    if (bitrate > 0) return '${(bitrate / 1000).round()}kbps';
    return 'جودة ${index + 1}';
  }

  // ---------------------------------------------------------------- إنهاء

  @override
  void dispose() {
    _disposed = true;
    _token++;
    final p = player;
    player = null;
    video = null;
    if (p != null) {
      unawaited(p.dispose().catchError((_) {}));
    }
    super.dispose();
  }
}
