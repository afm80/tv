import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart' as vp;

import '../data/models.dart';
import '../player/player_controller.dart';
import 'theme.dart';

/// شاشة المشغل: أفقية بملء الشاشة، بلا أشرطة نظام، وبلا أزرار للمحركات.
/// ExoPlayer وMPV يتبدلان تلقائياً في الخلفية. يظهر فقط (ويختفي بعد 3.5 ثانية):
///  - أزرار الروابط أعلى اليسار (إذا كان للقناة أكثر من رابط)
///  - زر ⚙ الجودة أعلى اليمين (إذا كان البث يحتوي أكثر من جودة)
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterFullscreen();
    _ctrl = SatPlayerController(channelName: widget.channel.name, links: widget.channel.links)..start();
    _scheduleHide();
  }

  /// أفقي + ملء الشاشة + إخفاء أشرطة النظام.
  void _enterFullscreen() {
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// الرجوع للوضع العمودي وإظهار أشرطة النظام.
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

  // ------------------------------------------------------------ إظهار/إخفاء الأزرار

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_menuOpen) return;
    _hideTimer = Timer(_idle, () {
      if (mounted && !_menuOpen) setState(() => _uiVisible = false);
    });
  }

  /// أي لمسة على الشاشة تُظهر الأزرار وتعيد العدّ.
  void _wake() {
    if (!_uiVisible) setState(() => _uiVisible = true);
    _scheduleHide();
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
            final hasQuality = _ctrl.qualities.length >= 2;
            return Stack(
              fit: StackFit.expand,
              children: [
                _video(),
                if (_ctrl.loading) _loader(),
                if (_ctrl.failureVisible) _failure(),
                if (hasLinks || hasQuality)
                  Positioned(
                    top: 10,
                    left: 12 + pad.left,
                    right: 12 + pad.right,
                    child: IgnorePointer(
                      ignoring: !_uiVisible,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: _uiVisible ? 1 : 0,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: hasLinks
                                  ? Align(
                                      alignment: Alignment.topLeft,
                                      child: _LinkBar(
                                        links: _ctrl.links,
                                        activeIndex: _ctrl.linkIndex,
                                        onSelect: (i) {
                                          _ctrl.selectLink(i);
                                          _wake();
                                        },
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            if (hasQuality) ...[
                              const SizedBox(width: 8),
                              _qualityMenu(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------ الفيديو (بدون أزرار)

  Widget _video() {
    final exo = _ctrl.exo;
    final video = _ctrl.video;
    if (exo != null) {
      return ValueListenableBuilder<vp.VideoPlayerValue>(
        key: ObjectKey(exo),
        valueListenable: exo,
        builder: (context, v, _) {
          final ratio = v.isInitialized && v.aspectRatio > 0 ? v.aspectRatio : 16 / 9;
          return Stack(
            fit: StackFit.expand,
            children: [
              Center(child: AspectRatio(aspectRatio: ratio, child: vp.VideoPlayer(exo))),
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
        fit: BoxFit.contain,
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

  // ------------------------------------------------------------ زر الجودة (أعلى اليمين)

  Widget _qualityMenu() {
    return PopupMenuButton<int>(
      color: const Color.fromRGBO(0, 0, 0, .92),
      position: PopupMenuPosition.under,
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
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color.fromRGBO(0, 0, 0, .65),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, .3)),
        ),
        child: Text('⚙ الجودة', style: cairo(size: 13, weight: 700)),
      ),
    );
  }
}

/// شريط روابط القناة: أعلى اليسار، يتمرر أفقياً عند كثرة الروابط.
/// الإخفاء والإظهار تتحكم به الشاشة الأم.
class _LinkBar extends StatelessWidget {
  const _LinkBar({required this.links, required this.activeIndex, required this.onSelect});

  final List<ChannelLink> links;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  static const double _fs = 13;

  String _labelOf(int i) => links[i].label.isNotEmpty ? links[i].label : 'رابط ${i + 1}';

  /// عرض المحتوى التقريبي كي لا يمتد الشريط على كامل العرض.
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
