import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart' as vp;

import '../data/models.dart';
import '../player/player_controller.dart';
import 'theme.dart';

const Color _kRed = Color(0xFFE62117);

/// شاشة المشغل بتصميم ياسين تيفي: أفقية بملء الشاشة بلا أشرطة نظام.
/// ExoPlayer وMPV يتبدلان تلقائياً في الخلفية بلا أزرار لهما.
/// أسفل الشاشة: ‎-10 ثوانٍ، تشغيل/إيقاف، ‎+10 ثوانٍ، إعادة تحميل، ⚙ الجودة (إن وُجدت)،
/// حجم الصورة، نافذة عائمة (PiP)، ثم شريط التقدم الأحمر. أعلى اليسار: أزرار الروابط.
/// كل ذلك يختفي بعد 3.5 ثانية (إذا كان البث يعمل) ويعود بلمس الشاشة.
class PlayerOverlay extends StatefulWidget {
  const PlayerOverlay({super.key, required this.channel});
  final Channel channel;

  @override
  State<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends State<PlayerOverlay> with WidgetsBindingObserver {
  static const Duration _idle = Duration(milliseconds: 3500);

  late final SatPlayerController _ctrl;
  Timer? _hideTimer;
  bool _uiVisible = true;
  bool _menuOpen = false;
  BoxFit _fit = BoxFit.contain;
  double? _drag; // موضع السحب على شريط التقدم (ms)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterFullscreen();
    _ctrl = SatPlayerController(channelName: widget.channel.name, links: widget.channel.links)..start();
    _scheduleHide();
  }

  void _enterFullscreen() {
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullscreen() {
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enterFullscreen();
      _ctrl.onAppResumed();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _exitFullscreen();
    _ctrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ إظهار/إخفاء

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_menuOpen) return;
    _hideTimer = Timer(_idle, () {
      if (!mounted || _menuOpen) return;
      // لا نخفي الأزرار والبث متوقف مؤقتاً.
      if (_ctrl.info.value.playing) {
        setState(() => _uiVisible = false);
      } else {
        _scheduleHide();
      }
    });
  }

  void _wake() {
    if (!_uiVisible) setState(() => _uiVisible = true);
    _scheduleHide();
  }

  void _cycleFit() {
    setState(() {
      _fit = switch (_fit) {
        BoxFit.contain => BoxFit.cover,
        BoxFit.cover => BoxFit.fill,
        _ => BoxFit.contain,
      };
    });
  }

  // ------------------------------------------------------------ البناء

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: Colors.black,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _wake(),
        onPointerMove: (_) => _wake(),
        child: ListenableBuilder(
          listenable: _ctrl,
          builder: (context, _) {
            final hasLinks = _ctrl.links.length >= 2;
            return Stack(
              fit: StackFit.expand,
              children: [
                _video(),
                if (_ctrl.loading) _loader(),
                if (_ctrl.failureVisible) _failure(),
                if (hasLinks)
                  Positioned(
                    top: 10,
                    left: 12 + pad.left,
                    right: 12 + pad.right,
                    child: IgnorePointer(
                      ignoring: !_uiVisible,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: _uiVisible ? 1 : 0,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: _LinkBar(
                            links: _ctrl.links,
                            activeIndex: _ctrl.linkIndex,
                            onSelect: (i) {
                              _ctrl.selectLink(i);
                              _wake();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                _controlsBar(pad),
              ],
            );
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------ الفيديو

  Widget _video() {
    final exo = _ctrl.exo;
    final video = _ctrl.video;
    if (exo != null) {
      return ValueListenableBuilder<vp.VideoPlayerValue>(
        key: ObjectKey(exo),
        valueListenable: exo,
        builder: (context, v, _) {
          final size = v.isInitialized && v.size.width > 0 && v.size.height > 0 ? v.size : const Size(1280, 720);
          return Stack(
            fit: StackFit.expand,
            children: [
              SizedBox.expand(
                child: FittedBox(
                  fit: _fit,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(width: size.width, height: size.height, child: vp.VideoPlayer(exo)),
                ),
              ),
              if (v.isBuffering && v.isInitialized && !_ctrl.loading)
                const Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: kOrange,
                      backgroundColor: Color.fromRGBO(255, 255, 255, .15),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }
    if (video != null) {
      return Video(
        key: ObjectKey(video),
        controller: video,
        controls: NoVideoControls,
        fit: _fit,
        fill: Colors.black,
      );
    }
    return const SizedBox.expand();
  }

  Widget _loader() {
    return Container(
      color: const Color.fromRGBO(0, 0, 0, .55),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: kOrange,
              backgroundColor: Color.fromRGBO(255, 255, 255, .15),
            ),
          ),
          const SizedBox(height: 10),
          Text('جاري تشغيل القناة...', style: cairo(size: 13, weight: 700)),
        ],
      ),
    );
  }

  Widget _failure() {
    return Container(
      color: const Color.fromRGBO(0, 0, 0, .85),
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_ctrl.failureText, textAlign: TextAlign.center, style: cairo(size: 13)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _ctrl.retryFromFailure,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Text('إعادة المحاولة', style: cairo(size: 14, weight: 700, color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ شريط التحكم السفلي (مثل ياسين تيفي)

  Widget _controlsBar(EdgeInsets pad) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !_uiVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _uiVisible ? 1 : 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(12 + pad.left, 30, 12 + pad.right, 6 + pad.bottom),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color.fromRGBO(0, 0, 0, .75), Color.fromRGBO(0, 0, 0, 0)],
              ),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buttonsRow(),
                  _progress(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon(IconData icon, VoidCallback onTap, {String? tip}) {
    return SizedBox(
      width: 60,
      height: 44,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buttonsRow() {
    final hasQuality = _ctrl.qualities.length >= 2;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _icon(Icons.replay_10, () => _ctrl.seekBy(const Duration(seconds: -10))),
        ValueListenableBuilder<PlaybackInfo>(
          valueListenable: _ctrl.info,
          builder: (context, i, _) => _icon(
            i.playing ? Icons.pause : Icons.play_arrow,
            _ctrl.togglePlay,
          ),
        ),
        _icon(Icons.forward_10, () => _ctrl.seekBy(const Duration(seconds: 10))),
        const SizedBox(width: 24),
        _icon(Icons.refresh, _ctrl.reload),
        if (hasQuality) _qualityMenu(),
        _icon(Icons.aspect_ratio, _cycleFit),
      ],
    );
  }

  Widget _qualityMenu() {
    return SizedBox(
      width: 60,
      height: 44,
      child: PopupMenuButton<int>(
        padding: EdgeInsets.zero,
        color: const Color.fromRGBO(0, 0, 0, .92),
        position: PopupMenuPosition.over,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onOpened: () {
          _menuOpen = true;
          _hideTimer?.cancel();
        },
        onCanceled: () {
          _menuOpen = false;
          _scheduleHide();
        },
        onSelected: (i) {
          _menuOpen = false;
          _ctrl.selectQuality(i);
          _scheduleHide();
        },
        itemBuilder: (context) => [
          for (var i = 0; i < _ctrl.qualities.length; i++)
            PopupMenuItem<int>(
              value: i,
              child: Text(
                _ctrl.qualities[i].label,
                style: cairo(size: 15, weight: 900, color: i == _ctrl.qualityIndex ? kAmber : Colors.white),
              ),
            ),
        ],
        child: const Center(child: Icon(Icons.settings, color: Colors.white, size: 28)),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _progress() {
    return ValueListenableBuilder<PlaybackInfo>(
      valueListenable: _ctrl.info,
      builder: (context, i, _) {
        final style = cairo(size: 12, weight: 700);
        if (i.live) {
          // بث مباشر: خط أحمر كامل بلا سحب.
          return SizedBox(
            height: 22,
            child: Center(child: Container(height: 3, color: _kRed)),
          );
        }
        final total = i.duration.inMilliseconds.toDouble();
        final pos = (_drag ?? i.position.inMilliseconds.toDouble()).clamp(0.0, total).toDouble();
        return SizedBox(
          height: 22,
          child: Row(
            children: [
              Text(_fmt(Duration(milliseconds: pos.round())), style: style),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: _kRed,
                    inactiveTrackColor: const Color.fromRGBO(255, 255, 255, .3),
                    thumbColor: _kRed,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    min: 0,
                    max: total,
                    value: pos,
                    onChanged: (v) {
                      setState(() => _drag = v);
                      _wake();
                    },
                    onChangeEnd: (v) {
                      _ctrl.seekTo(Duration(milliseconds: v.round()));
                      setState(() => _drag = null);
                    },
                  ),
                ),
              ),
              Text(_fmt(i.duration), style: style),
            ],
          ),
        );
      },
    );
  }
}

/// شريط روابط القناة: أعلى اليسار، يتمرر أفقياً عند كثرة الروابط.
class _LinkBar extends StatelessWidget {
  const _LinkBar({required this.links, required this.activeIndex, required this.onSelect});

  final List<ChannelLink> links;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  static const double _fs = 13;

  String _labelOf(int i) => links[i].label.isNotEmpty ? links[i].label : 'رابط ${i + 1}';

  double _contentWidth() {
    var total = 20.0;
    for (var i = 0; i < links.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: _labelOf(i), style: cairo(size: _fs, weight: 700)),
        textDirection: TextDirection.rtl,
        maxLines: 1,
      )..layout();
      total += tp.width + 28 + (i > 0 ? 6 : 0);
    }
    return total + 2;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : double.infinity;
        final width = _contentWidth().clamp(0.0, maxW).toDouble();
        return SizedBox(
          width: width,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < links.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    _chip(i),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(int i) {
    final active = i == activeIndex;
    return GestureDetector(
      onTap: () => onSelect(i),
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? kAmber : const Color.fromRGBO(0, 0, 0, .55),
          borderRadius: BorderRadius.circular(999),
          border: active ? null : Border.all(color: const Color.fromRGBO(255, 255, 255, .3)),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            _labelOf(i),
            maxLines: 1,
            style: cairo(size: _fs, weight: 700, color: active ? Colors.black : Colors.white),
          ),
        ),
      ),
    );
  }
}
