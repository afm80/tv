import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

dynamic _decodeJson(String s) => jsonDecode(s);

Future<dynamic> _decode(String s) async {
  // الحمولة الكبيرة (آلاف القنوات) تُفكّ في isolate حتى لا يتجمد التطبيق.
  if (s.length > 100000) return compute(_decodeJson, s);
  return jsonDecode(s);
}

/// يستمع لعقدة في Firebase Realtime Database عبر REST + Server-Sent Events،
/// فيعطي نفس سلوك `ref(path).on('value')` في الموقع: قيمة أولية ثم تحديثات حيّة،
/// دون الحاجة لإعداد Firebase داخل أندرويد (القراءة عامة كما في الموقع).
class RtdbValueStream {
  RtdbValueStream(this.path, this.onValue);

  final String path;
  final void Function(dynamic value) onValue;

  bool _stopped = false;
  bool _started = false;
  dynamic _data;
  Timer? _debounce;
  http.Client? _client;
  int _failures = 0;

  Uri get _uri => Uri.parse('$kDatabaseUrl/$path.json');

  void start() {
    if (_started) return;
    _started = true;
    _stopped = false;
    unawaited(_loop());
  }

  void stop() {
    _stopped = true;
    _started = false;
    _debounce?.cancel();
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
  }

  /// يعيد الاتصال فوراً (مثلاً بعد عودة التطبيق من الخلفية).
  void reconnect() {
    try {
      _client?.close();
    } catch (_) {}
  }

  Future<void> _loop() async {
    var gotData = false;
    while (!_stopped) {
      try {
        await _stream((first) => gotData = gotData || first);
        _failures = 0;
      } catch (e) {
        _failures++;
        if (kDebugMode) debugPrint('RTDB[$path] stream error: $e');
        // إن لم تصل أي بيانات بعد، نجرّب طلباً عادياً كاحتياط.
        if (!gotData) {
          try {
            final res = await http.get(_uri).timeout(const Duration(seconds: 30));
            if (res.statusCode == 200) {
              _data = await _decode(utf8.decode(res.bodyBytes));
              gotData = true;
              _emit(immediate: true);
            }
          } catch (_) {}
        }
      }
      if (_stopped) break;
      final secs = min(30, 2 << min(_failures, 4));
      await Future<void>.delayed(Duration(seconds: _failures == 0 ? 1 : secs));
    }
  }

  Future<void> _stream(void Function(bool first) onFirst) async {
    final client = http.Client();
    _client = client;
    try {
      final req = http.Request('GET', _uri)
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw http.ClientException('HTTP ${res.statusCode}', _uri);
      }
      String? event;
      final dataBuf = StringBuffer();
      final lines = res.stream
          .timeout(const Duration(seconds: 75)) // Firebase يرسل keep-alive كل ~30 ثانية
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (_stopped) return;
        if (line.isEmpty) {
          if (event != null) {
            final fin = await _dispatch(event, dataBuf.toString());
            if (fin) onFirst(true);
          }
          event = null;
          dataBuf.clear();
          continue;
        }
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          var d = line.substring(5);
          if (d.startsWith(' ')) d = d.substring(1);
          if (dataBuf.isNotEmpty) dataBuf.write('\n');
          dataBuf.write(d);
        }
      }
    } finally {
      try {
        client.close();
      } catch (_) {}
      if (identical(_client, client)) _client = null;
    }
  }

  /// يعيد true عند وصول بيانات (put/patch).
  Future<bool> _dispatch(String event, String data) async {
    switch (event) {
      case 'put':
      case 'patch':
        final msg = await _decode(data);
        if (msg is! Map) return false;
        final p = (msg['path'] ?? '/').toString();
        _apply(p, msg['data'], merge: event == 'patch');
        _emit();
        return true;
      case 'cancel':
      case 'auth_revoked':
        throw StateError('RTDB $event');
      default: // keep-alive
        return false;
    }
  }

  void _emit({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      onValue(_data);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 150), () => onValue(_data));
  }

  // ---------- تطبيق put/patch على النسخة المحلية ----------

  void _apply(String path, dynamic data, {required bool merge}) {
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    if (merge) {
      if (data is Map) {
        data.forEach((k, v) => _put([...segs, k.toString()], v));
      }
    } else {
      _put(segs, data);
    }
  }

  void _put(List<String> segs, dynamic data) {
    if (segs.isEmpty) {
      _data = data;
      return;
    }
    if (_data is! Map) {
      _data = _data is List ? _listToMap(_data as List) : <String, dynamic>{};
    }
    var node = _data as Map;
    for (var i = 0; i < segs.length - 1; i++) {
      var child = node[segs[i]];
      if (child is List) {
        child = _listToMap(child);
        node[segs[i]] = child;
      }
      if (child is! Map) {
        child = <String, dynamic>{};
        node[segs[i]] = child;
      }
      node = child;
    }
    final last = segs.last;
    if (data == null) {
      node.remove(last);
    } else {
      node[last] = data;
    }
  }

  Map<String, dynamic> _listToMap(List l) {
    final m = <String, dynamic>{};
    for (var i = 0; i < l.length; i++) {
      if (l[i] != null) m['$i'] = l[i];
    }
    return m;
  }
}
