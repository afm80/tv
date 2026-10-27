import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/models.dart';
import '../player/player_controller.dart';
import 'site_background.dart';
import 'theme.dart';

/// شاشة المشغل (playerContainer + satPlayer في الموقع).
class PlayerOverlay extends StatefulWidget {
  const PlayerOverlay({super.key, required this.channel});
  final Channel channel;

  @override
  State<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends State<PlayerOverlay> with WidgetsBindingObserver {
  late final SatPlayerController _ctrl;
  final GlobalKey<_LinkBarState> _barKey = GlobalKey<_LinkBarState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl = SatPlayerController(channelName: widget.channel.name, links: widget.channel.links)..start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ctrl.onAppResumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const SiteBackground(),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: ListenableBuilder(
                    listenable: _ctrl,
                    builder: (context, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _videoWrap(),
                        const SizedBox(height: 10),
                        _controls(),
                        if (_ctrl.msg.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(0, 0, 0, .7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(_ctrl.msg, style: cairo(size: 13)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ الفيديو

  Widget _videoWrap() {
    final video = _ctrl.video;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color.fromRGBO(0, 0, 0, .3), offset: Offset(0, 6), blurRadius: 20),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _barKey.currentState?.wake(),
            onPointerMove: (_) => _barKey.currentState?.wake(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                if (video != null)
                  Video(
                    key: ObjectKey(video),
                    controller: video,
                    controls: MaterialVideoControls,
                    fill: Colors.black,
                  ),
                if (_ctrl.loading) _loader(),
                if (_ctrl.failureVisible) _failure(),
                if (_ctrl.links.length >= 2)
                  Positioned(
                    top: MediaQuery.sizeOf(context).width <= 600 ? 4 : 6,
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _LinkBar(
                        key: _barKey,
                        links: _ctrl.links,
                        activeIndex: _ctrl.linkIndex,
                        onSelect: _ctrl.selectLink,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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

  // ------------------------------------------------------------ أزرار التحكم

  Widget _controls() {
    final primary = _ctrl.mode == PlayerMode.primary;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_ctrl.showRetry) _retryButton(),
        _SwitchButton(label: 'المشغل الرئيسي', active: primary, onTap: _ctrl.choosePrimary),
        _SwitchButton(label: 'المشغل الاحتياطي', active: !primary, onTap: _ctrl.chooseBackup),
        if (primary) _engineSelect(),
        if (primary && _ctrl.qualities.length >= 2) _qualityMenu(),
      ],
    );
  }

  Widget _retryButton() {
    return GestureDetector(
      onTap: _ctrl.retry,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color.fromRGBO(0, 0, 0, .75),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, .3)),
        ),
        child: Text('↻', style: cairo(size: 20, weight: 900)),
      ),
    );
  }

  Widget _engineSelect() {
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: _boxDecoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<EngineChoice>(
          value: _ctrl.engine,
          dropdownColor: const Color.fromRGBO(0, 0, 0, .92),
          iconEnabledColor: Colors.white,
          style: cairo(size: 15, weight: 900),
          items: [
            DropdownMenuItem(value: EngineChoice.auto, child: Text('تلقائي', style: cairo(size: 15, weight: 900))),
            DropdownMenuItem(
                value: EngineChoice.hw, child: Text('المشغل الأصلي', style: cairo(size: 15, weight: 900))),
            DropdownMenuItem(
                value: EngineChoice.sw, child: Text('المشغل البرمجي', style: cairo(size: 15, weight: 900))),
          ],
          onChanged: (v) {
            if (v != null) _ctrl.setEngine(v);
          },
        ),
      ),
    );
  }

  Widget _qualityMenu() {
    return PopupMenuButton<int>(
      color: const Color.fromRGBO(0, 0, 0, .92),
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: _ctrl.selectQuality,
      itemBuilder: (context) => [
        for (var i = 0; i < _ctrl.qualities.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(_ctrl.qualities[i].label, style: cairo(size: 15, weight: 900)),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        alignment: Alignment.center,
        decoration: _boxDecoration(),
        child: Text('⚙ الجودة', style: cairo(size: 15, weight: 900)),
      ),
    );
  }
}

BoxDecoration _boxDecoration({Color? color}) => BoxDecoration(
      color: color ?? const Color.fromRGBO(0, 0, 0, .75),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color.fromRGBO(255, 255, 255, .3)),
    );

class _SwitchButton extends StatelessWidget {
  const _SwitchButton({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        alignment: Alignment.center,
        decoration: _boxDecoration(color: active ? kAmber : null),
        child: Text(label, style: cairo(size: 15, weight: 900, color: active ? Colors.black : Colors.white)),
      ),
    );
  }
}

/// شريط روابط القناة (sat-link-buttons): أعلى يسار المشغل، يتمرر أفقياً
/// ويختفي بعد 3.5 ثانية من عدم التفاعل.
class _LinkBar extends StatefulWidget {
  const _LinkBar({super.key, required this.links, required this.activeIndex, required this.onSelect});

  final List<ChannelLink> links;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  @override
  State<_LinkBar> createState() => _LinkBarState();
}

class _LinkBarState extends State<_LinkBar> {
  static const Duration _idle = Duration(milliseconds: 3500);
  bool _idleNow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_idle, () {
      if (mounted) setState(() => _idleNow = true);
    });
  }

  void wake() {
    if (_idleNow) setState(() => _idleNow = false);
    _schedule();
  }

  TextStyle _chipStyle(bool small, bool active) => cairo(
        size: small ? 12 : 13,
        weight: 700,
        color: active ? Colors.black : Colors.white,
      );

  String _labelOf(int i) => widget.links[i].label.isNotEmpty ? widget.links[i].label : 'رابط ${i + 1}';

  /// عرض المحتوى التقريبي كي لا يغطي الشريط كامل عرض الفيديو (max-width في الموقع).
  double _contentWidth(bool small) {
    var total = 20.0; // padding أفقي للشريط 10 + 10
    for (var i = 0; i < widget.links.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: _labelOf(i), style: _chipStyle(small, true)),
        textDirection: TextDirection.rtl,
        maxLines: 1,
      )..layout();
      total += tp.width + 2 * (small ? 12 : 14) + (i > 0 ? 6 : 0);
    }
    return total + 2;
  }

  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.sizeOf(context).width <= 600;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth - 10 : double.infinity;
        final width = _contentWidth(small).clamp(0.0, maxW).toDouble();
        return IgnorePointer(
          ignoring: _idleNow,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            offset: _idleNow ? const Offset(0, -0.25) : Offset.zero,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _idleNow ? 0 : 1,
              child: SizedBox(
                width: width,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < widget.links.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _chip(i, small),
                        ],
                      ],
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

  Widget _chip(int i, bool small) {
    final active = i == widget.activeIndex;
    final label = _labelOf(i);
    return GestureDetector(
      onTap: () {
        widget.onSelect(i);
        wake();
      },
      child: Container(
        constraints: BoxConstraints(minHeight: small ? 30 : 32),
        padding: EdgeInsets.symmetric(horizontal: small ? 12 : 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? kAmber : const Color.fromRGBO(255, 255, 255, .22),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            label,
            maxLines: 1,
            style: cairo(
              size: small ? 12 : 13,
              weight: 700,
              color: active ? Colors.black : Colors.white,
              shadows: active
                  ? null
                  : const [Shadow(color: Color.fromRGBO(0, 0, 0, .6), offset: Offset(0, 1), blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }
}
