import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart' as vp;

import '../data/models.dart';
import '../player/player_controller.dart';
import 'theme.dart';

const Color _kRed = Color(0xFFE62117);

/// جسر أصلي (MainActivity.kt يولّده tool/patch_android.py): نافذة عائمة (PiP) وإعدادات البث.
const MethodChannel _kNative = MethodChannel('app.alfaham/native');

/// شاشة المشغل: أفقية بملء الشاشة بلا أشرطة نظام.
/// ExoPlayer وMPV يتبدلان تلقائياً في الخلفية بلا أزرار لهما.
/// أعلى اليسار: رجوع. أعلى اليمين: شعار/اسم القناة + إعادة تحميل.
/// وسط الشاشة (شريط عائم): ‎-10، ⚙ الجودة، بث، حجم الصورة، تشغيل/إيقاف، ملء الشاشة، نافذة عائمة، ‎+10.
/// أسفل الشاشة: شريط التقدم ثم كروت روابط القناة.
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
  bool _fullscreen = true;
  String? _toast;
  Timer? _toastTimer;
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
    _toastTimer?.cancel();
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
    _showToast(switch (_fit) {
      BoxFit.cover => 'ملء الشاشة',
      BoxFit.fill => 'تمديد',
      _ => 'الحجم الأصلي',
    });
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      _enterFullscreen();
    } else {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _enterPip() async {
    setState(() => _uiVisible = false);
    try {
      await _kNative.invokeMethod('enterPip');
    } catch (_) {
      if (!mounted) return;
      setState(() => _uiVisible = true);
      _showToast('النافذة العائمة غير مدعومة على هذا الجهاز');
    }
  }

  Future<void> _openCast() async {
    try {
      await _kNative.invokeMethod('openCast');
    } catch (_) {
      _showToast('البث غير متاح على هذا الجهاز');
    }
  }

  Widget _fade(Widget child) {
    return IgnorePointer(
      ignoring: !_uiVisible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _uiVisible ? 1 : 0,
        child: child,
      ),
    );
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
            return Stack(
              fit: StackFit.expand,
              children: [
                _video(),
                if (_ctrl.loading) _loader(),
                if (_ctrl.failureVisible) _failure(),
                _bottomBar(pad),
                _topBar(pad),
                Positioned.fill(child: _fade(Center(child: _centerControls()))),
                if (_toast != null)
                  Positioned(
                    top: 56,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(0, 0, 0, .7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(_toast!, style: cairo(size: 13, weight: 700)),
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

  // ------------------------------------------------------------ الشريط العلوي: رجوع + شعار القناة + إعادة تحميل

  Widget _topBar(EdgeInsets pad) {
    return Positioned(
      top: 8,
      left: 8 + pad.left,
      right: 8 + pad.right,
      child: _fade(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              _icon(Icons.arrow_back, () => Navigator.of(context).maybePop(), tip: 'رجوع', width: 48),
              const Spacer(),
              _logo(),
              const SizedBox(width: 4),
              _icon(Icons.refresh, _ctrl.reload, tip: 'إعادة تحميل', width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(0, 0, 0, .55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.channel.img.isNotEmpty) ...[
            CachedNetworkImage(
              imageUrl: widget.channel.img,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                widget.channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cairo(size: 13, weight: 700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ شريط الأزرار العائم في الوسط

  Widget _icon(IconData icon, VoidCallback onTap, {String? tip, double width = 52, double size = 28}) {
    return SizedBox(
      width: width,
      height: 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  Widget _centerControls() {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _icon(Icons.replay_10, () => _ctrl.seekBy(const Duration(seconds: -10)), tip: 'رجوع 10 ثوانٍ'),
          _qualityMenu(),
          _icon(Icons.cast, _openCast, tip: 'بث'),
          _icon(Icons.aspect_ratio, _cycleFit, tip: 'حجم الصورة'),
          ValueListenableBuilder<PlaybackInfo>(
            valueListenable: _ctrl.info,
            builder: (context, i, _) => _icon(
              i.playing ? Icons.pause : Icons.play_arrow,
              _ctrl.togglePlay,
              tip: 'تشغيل / إيقاف',
              size: 34,
            ),
          ),
          _icon(
            _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            _toggleFullscreen,
            tip: 'ملء الشاشة',
            size: 30,
          ),
          _icon(Icons.picture_in_picture_alt, _enterPip, tip: 'نافذة عائمة'),
          _icon(Icons.forward_10, () => _ctrl.seekBy(const Duration(seconds: 10)), tip: 'تقديم 10 ثوانٍ'),
        ],
      ),
    );
  }

  Widget _qualityMenu() {
    final has = _ctrl.qualities.length >= 2;
    return SizedBox(
      width: 52,
      height: 48,
      child: PopupMenuButton<int>(
        padding: EdgeInsets.zero,
        tooltip: 'الإعدادات',
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
        itemBuilder: (context) => has
            ? [
                for (var i = 0; i < _ctrl.qualities.length; i++)
                  PopupMenuItem<int>(
                    value: i,
                    child: Text(
                      _ctrl.qualities[i].label,
                      style: cairo(size: 15, weight: 900, color: i == _ctrl.qualityIndex ? kAmber : Colors.white),
                    ),
                  ),
              ]
            : [
                PopupMenuItem<int>(
                  enabled: false,
                  value: -1,
                  child: Text('لا توجد خيارات جودة', style: cairo(size: 14, weight: 700)),
                ),
              ],
        child: const Center(child: Icon(Icons.settings, color: Colors.white, size: 28)),
      ),
    );
  }

  // ------------------------------------------------------------ الشريط السفلي: التقدم + كروت الروابط

  Widget _bottomBar(EdgeInsets pad) {
    final hasLinks = _ctrl.links.length >= 2;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: _fade(
        Container(
          padding: EdgeInsets.fromLTRB(12 + pad.left, 30, 12 + pad.right, 8 + pad.bottom),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color.fromRGBO(0, 0, 0, .8), Color.fromRGBO(0, 0, 0, 0)],
            ),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _progress(),
                if (hasLinks) ...[
                  const SizedBox(height: 8),
                  _LinkBar(
                    links: _ctrl.links,
                    activeIndex: _ctrl.linkIndex,
                    onSelect: (i) {
                      _ctrl.selectLink(i);
                      _wake();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
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

/// كروت روابط القناة: أسفل الشاشة، تتمرر أفقياً عند كثرتها، والرابط الحالي بإطار مميّز.
class _LinkBar extends StatelessWidget {
  const _LinkBar({required this.links, required this.activeIndex, required this.onSelect});

  final List<ChannelLink> links;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  String _labelOf(int i) => links[i].label.isNotEmpty ? links[i].label : 'رابط ${i + 1}';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: links.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _card(i),
      ),
    );
  }

  Widget _card(int i) {
    final active = i == activeIndex;
    return GestureDetector(
      onTap: () => onSelect(i),
      child: Container(
        width: 88,
        padding: const EdgeInsets.fromLTRB(5, 5, 5, 3),
        decoration: BoxDecoration(
          color: active ? const Color.fromRGBO(255, 193, 7, .22) : const Color.fromRGBO(255, 255, 255, .12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? kAmber : Colors.transparent, width: 2),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? kAmber : const Color.fromRGBO(255, 255, 255, .18),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${i + 1}',
                  style: cairo(size: 15, weight: 900, color: active ? Colors.black : Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                _labelOf(i),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cairo(size: 11, weight: 700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
